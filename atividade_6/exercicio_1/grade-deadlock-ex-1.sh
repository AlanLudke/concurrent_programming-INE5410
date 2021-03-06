#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
�      �<�V۸��;y
�ЎH�WKf(�-k(�Bz�3�x�D!>M���s��=��#������eGv�Rz��f�X��_���ڒ�h�R��_x�͞<������.�Է|��V���Օ��Z��Tk< �ߎ������Џn�7�������|~�Qp��_\^���;y��8�jo�u"��nI�i��T_�������R����߼�g.���©�Ko6_����;����z����a{�^���J\����$]�D��#Gd���*����I�D}�A!�	�"��ffǉ�1��0,�
����8��k-/�k'�3<u� p�8"G�wFfc�> D��85h8C����tR�ͅ���[b�߻+��Sh��Dc����Y�o,����]<��?������㶏>�Q
i�T[.1ߏ�òفi!�~f������ov������g����G�>)[�ǟ�`v���~|ܰmfv
|�Ide@�A�,��ov[*O���.�8���Hp�����{Z}�d��,p��z���јf�����oy�Q����xT��������mo��o���k��.����ދ�٥��Vk���֯��%>���L+K��$Y���x0`A��C�Y�SF ���e��s�*|?d#ƀxO�5��5�f�"<�x�ᗿ>���!��Q��pD���d�!��w���y���2���%��T���J�K�ۜᇠUQJ���j�ޅ�է��������F�Σ��KH��b��� Y����1Ʀ�cq��WV����N��K/6�[���6� �(�ߍR�E��O0 c8C	���}�!�lG�q�FƟ�CE���Gi���/¤pS����M��52[�\�>"��G@�� �ٚg�#?`�#r��9�AN����x=rF�*DM�"bZ�3�=k��ٳw�gͳ �H��gc���/333��5Dh��w��j��I���}�t���-���^��yހF��c���f$"� �ܬiJع�eI"�,��vR^�� �d�Q2R�iD%&�fͫʲ�eZ!�Q��]�J�9Ό��ۗ���m�{} �������-uX�5n0�RP�I�E���b
�Y���́�a­ǘuK�q���*����	q�b$iZe��"��*Ɓ�p��1�d	�S,�\$s��9�C��Q�zQ����c�B�K��Vj�����T��wb�ACD�����) b�0uɭ<eaì)� �_�Å��Zma��G� )G���'��?8��D~P�����B'��������:��_�߯���q{^���m������f{��n���Z{[/헶]��j�7�4�z��<�Oa�u����F����E�c	���gG���O2�N�	�$�V���w�i�.������~2��7��&lm�xͮ?>�	�} �n��s�C�����jQzYPO���N��$��[��?:w�N����|c/t�<pn	��&��̠E�H
ڃ�9(���n?���QaE�)m��i��Δ��#M�c�a�vM��w���\V�w8p;�}�yM� \�M E�E4� v��� 3�(���7�L)��k��p4����g��,C[@U�?�.|�	郱gw���o��o��U�BpL��"����n�!��PU	#k�b*�h�+i��γY��b�*��c$8$�mV����8,�s]Ny�~���x���
��������21�7�����x
�i'����9��3��=M�� �2�С:�t��s�u�l�D�Lˋp�L���F��#<�I���>�^�l2�W"�vq�JA�\o�w�#n��b^�9mwV]m����;{;mX�0�bj>Vg�yI�Bj��>|��ǰmn�ON뉦o�D����an�\7���FQ?��TS�
�=�E�G;*RC�}y��{�����4�ϓ����4��W�%��4�f�Rt1�8�D�����ca�����$���bs��$'��f�23Dl��S�0�r$��Q/j6᧘��r���Y'g <�B+3�"!�E�H� =+�H���j;��V�K�D�X0&c쬆y�ƾ�
1Q�N�ܬ�A�����v��kz�|�M��A��Ƒv�\�T�`�ϐ�⺀��:�5b�T������(Ĵ��G\�#?4��@E��.�^@)�2��X��T�!����2O�\�ЉᚓP)�X��7$��pd��/"���Ț6��eb�:2Ŏ���u~H�|��D�K!�Z?��X�� &e�P��P,�`����u|�mVTa58��Hq�+)p^PnÀ�*�:b*h��u$@���p��x���اDl22֐�*�d�>WO�Q�l�J#�HB��NG_?W���t=���e���G�
z]�J8�a�ű��u��l�Ko0��t`�����(��
�6D�K�PV~m�&I���40�����F��ghE�1cDD$)P�N�J0��bE�x�)���Z�&)$Ԑ�dtކA��97����d�I�y̢��ؕ8�q�x�K=�9�)A2�x�B��3Y�Ê�i�4+���~Z����x>��8
Ep�����W!^�*�ѣ�d�K�2#ia�u0:��h�0��.^������v�*���A&���F��t�HO9Q���|_�t�.\�� P�Ɨ�&�Gl��sqX��_J��;�M�u���n.0��= �m�*��$1�aՔ�|ziF��1>���:Q��*l��ӵ�#&�:I�R�\l���dbG�8%;4 X��>�N�ל��g��&�:�'J�0��{q|H��P����{�/7�^Xꠑ�ow�cں��� �@B:���/`�-6;lo��bӦ�!;����i`|����}�(dzu=��� ��C�[�k�g�d�r�D�:%ٟn%�Fh�����z��+�fۭ�WмX�7���"��� �P��T
�7P*'����/��.-2�����S�����"?)��8Ԭ6s4(Υ)��F�� ׫3��8!P��	n���m�vAI��)^�	YS�Q f�6j:׫�W17������6���O�+�ј_\��h�Q�����*|-�?y�^�ړ
Y�_}����Z_�����/-	TK� ,�?]����r_�OV��/ί<Ya�%��3��է�ܸ�l!�v�	�N���Ӂ=��D����{�Q%f�q:�@dC&�R�?i���&���,N�s�lNsY�~b4�����0�'��'�*�,pm����+#P�=���~0 9'�6���"v��պt"*e(��"���m9�R��u�S���@�
� �1e�� s1��(�_�i�ۖ7ڸ���˫m^�!�¨�Q�$���Qs4���[[�v �O:���K7
a_V���:��C���-�u�g�$i�^MP@��-_{�X��t6�a��q�jU�5�_�efs�@�J�CZ6|Ģҽ.[fS�X8j� �V�{��*��fUԈ$� S�Xt��� �bj�b�\�O�T���br��2��1����a jBk�d�"������d��v����Z\Y����G�����ѝ���	�� J9۩Jq�O��a�,ƀ?�r���l�QT`���"��)���Q'�6�3�wF�s꼇��0�e�)�������c7��Ҁ���k��V��G�;��q:L�l��X��v�0Ô�C�D|�@�Y�a#�!�p!���K��X��VE(�5��~E�����z�<�C�Gd�~�2�����x�X�PSAU<�R�����:��Z�mp/��I�;_�����X�N���13�n ���W�y|�2��F(��f�;�̠�z�f��T��'Xcp�ޘNS�5�I�`@�E���z��Q̆8ݬ��z��L�~۞f�U���m�,M03C��Gu��퓏��O���S��Rc���"�������?3d�F�9�'�Ft�0��q}̈�C~�#�uB~��SZ���X���ӱJۭvk��ڶ���g��C����?��>*o]�럇�^;K���m�d�����*1(�xݶ���˓Z�7�������9P�)g14Gƴ'����`%�Օ�Rv=)�C���!��k`��$�o�%x������L�N���YsĪT��JY�u-�[[W��v�b����G�	��-2p��4��Z��z��Bg�V�֪l;������^[�����n=?\��7�-�����^��'�~����޲��l���ړ���Ɇ�dG�}E���x�O��������_˫KY�����.���u��Aks;w��ֳ���!�����i�"Da����~��k3cO_�DI�*��#�Y��=4N��:g�B���r<�=:��D`���!���<4̎И�$�:�l��p��sjG��3�e'8+/��BS�� �ǈ�a��Y@��[D. �c��&�SIO$&s1��q��WHN����K�r���0�JH�ߙ8��:$��PA8ᐓ �81�[z,���JR)N!1,���Ė��Tz�5�>�x�֞�A@T؄�J�R��P@�z�~*]Txڈ�b�Rhf�2��k�	���暽2�
M:�1f�zk5�x��:�ct�4*����jU��S<������vnM���W�؛������]<�O�e(3Vw��x7���
�'|�v�$:����
�k��ܫb��:b�,�Y�T(�ݲ�O�.��팃��@�R����=q�M�_Q����V��Dܪ.d�?}	����xI�E�>�l�������*�Ty��2�2��%7g����|4��S�S#��tf�N�`�فC����JC�C��\	��N��{zaG���	
t;لE�?� ��ș�՛v�������A�E��a�k��g�̖����^���Q\^ͼ��hMIն7_��m�RAe5P2�ix�+Id�{eF�_a��K��gPb��Rb�q�XO=��;`[�ɝ������?�d�^��?���k?h���#�� N�3�����''�fTJ?�C��Z�?'�GDf���f�T
�N��I]�Q��+��=����	\���ᗿ�����R)�!�1�5~��Kum��A��$� ]4�I�CZ<��~��ʲ� k�-�Af�F�2K�����Dz~ȩ���P�y�<W������+s� X�L)�	�����:)tu�VV�j+>�^���ٵ�O��週�yc�S������E��%���p�S�Kd��ׂ�ٖI�¡Vp�c,��&�JvsYN��;��ͻH�m�gA��m%�'�U�-�d�!�Q����"t��8�!��J�Ift�0�b�8�n�[Kj*d�Wf�0�e�o�"�#�vZ��o�7d�淽�1O�]�q�>�7Q��}�J����dGI�%q:�u��T<���(vB/���V�Z2ɸC�;\r�9׻�4�E4qq�P�	��e�Wl~� ���W@_e]�ya�s��7<����8+�o��诚洬��\��������G4�sa5�+�]V�D�q:%�UB|�>����T�c�A٪��7L��j�	�y?v���ï�+����!luCM����H�߾G�]I�h$�,o�_j��q�F}�y��;��SŚ�����&��>V�O�'�XB
��GJVl8���SQ)0� �j���{����i��e+�&��I	*DA��l�bT�n��HQD!���1Ó��n=�u�hea��EM����� �!Iį�#X�I�<�������v�ۄHWe��jq��2F��������:l����-P1����ql_�����x�M����#r[�O��ê�~�On������^���pD*��+gf'U�ދVae�,>/�V��~s��l�%0����(~==�R��W<ڝ�t=�2���q��C�,&����=]s�6�Ϟ_)�j(iF#EJ�{���Օl�,9��Tv�")��p8!gƉ��1y��T�S�^�U� 	���H���T%�`��h4����=Q�u�(Pw7��`A��y�e,�X����$;����N��"({Y�'��������ٴ9><;�	�-Y��Wg����p#� I�C����]�:�X�M�	N<�?����F���1m��	W乼/}��\ .ͷ
re�xH�g�:����H��W$���-h	�
�`������=�Ĉ���̖_�~uv�͑��˛����U��@&;������F�i:iZh����X�N�j�p�:Y򖜲QK�/%��G���u]A]_mn>�ٻ��~�t�Fgcj�i�����1W@V���2���ێ�t�r�ŷT�ct�&�6��У޵J��r�T.L6�U�T]�����!��D&͛
������
��r�H���2��9E��u��[&}*5>�˭�bҊ����������шt>�2ٷ�n2�<��Z����l��~�u?�*ӦX�8��>F^H5���8�ߗ�$,�o�-�ⓁI��GY�*˺/�}�^O������ݽ����yi����nZ%,�S�XȲ*�)��ɥ����,���v^�ne��ŀIP��#(ٰ���؋�`�����H�`���j3!���f"o�ڰ�.����!hf:)�Y����YǗT22LcJN2a��ӠR�,n���o$� ]�U��`�����Ⱦ�Y(�ߙD�n,z�q#����͸�s�U�9zM��(V���j��5��s;v�8�=�%pU�%�*�ެ��sC�}�����a;�9��
����m���3�zT���8�~��w��υ��Ň����:Ю��W
�_�d2���cf3Ϊ�m
��:��Za�C���fs�J�Ӡ�؂L�#/�ٗ���!�F��:�E�h�[�2�Ki��I�x��/78;�����mE�*��#=}�w�
EH�Y����V�,|\e�W!e+-:o�߹���,৔��]�N�Qh�����H�.��F��4��I�(�V�9]"���� ��<,��c鴈���.���HW�s��N�/��(
�9HX�EhZLB$��&а|	���|k!�.�F���lm�g��k�XPQ}�K牌�m��������&�=껩��L���_�5��d^gߪ��׀h\��\cS�,��7썸]�a0	J�F'��9`>�����-�rP�%X�1���ѹ������bA���^ft\�*�%�p�Pz|��D�{]~�Pv���K��/����*=v0�x<y�-�7�1��*�	�^<�d�4����F�*�Tq��l���Ԧ��7��.<;,��1`���d������lʘ�t���x�~�)��c$��L#��RƩ����kw���^���ɫ�]]en2�l�����v�,��`�cү=�	�m���N:����Ѽ����S�����2L�(��6e4��J�!�$��M K��riy��T8�B��խ��l�[��!��Ն�=�_
�����C!tV})���_�\N젱8O�\���i��������L�B�K�����{ₜ&EV��vM��q��ˤ�U7҅vWc,hq�n/8� x�_=���rx�y�� _��Gf���
�蛃gjE���l��H�Q�F�C`]��m����,��Fe���պ�{-��'�:�܏G.ށ�Q���t$[dh���Zʚ*�>�`5ֱ���-6��>KW�LJ"v:%s�F2&�4��(?����$��-�վ4̐��}�kD�
�!����C�9x����M.S4c̪r�d>?t��:VϐE��1��x��;�Ux��e�������Uo�e�l��M����j@�%r�YXW����Q�Y�T�ـA�N�������j���P}�	b��>6����W�#���Ѧ�T���j8�P��at�9ƶ��Jc��J�j6�w�m0�dc�s��/D�>XG��F$!�
�M����>;:?~~����yFU�g�mnR����Ԑr�5d�� �&#�|�փ�?�H�~�1�Q=�����C� M�-o0����P���)�]+� �aM�&1�ʥ|G�8��w-��!�ꨳ�ok)��[j"����k�~_����������Rd.Q���6Q�W|��1�[l�Y��U��� 8Ӝ�]�r��\��G���v��GJ)0��B ![�䕪�q�n��oI��6�x|�NC��(b4�?����ǣI&8��[��oh��*;�iF]!�5�[q-��	��~���S~��=��x��$$���hA�+��Nd�غt�����q�e
�>��l��W	��@�h���>���|��z-.T�n�ëX�a/�lS����j�E�".�%�iZ��&"A�`)�=F���:�Ω�4�$��֣�a!0wcJ\�I}���􃊏]�W���s̰�S�6`Ţ�����Lgm��YIU�������U�o9�bq�^�u��cF|����y���~��&o��FV�X���K���ϕ����E�Ϳ�N�.�J�]*@�wfE �F�R���ᭊ~��gY[o*S�����Ś�?ϡ� m�����*���Y���4�z��	��^�� ���S�Ë�4�e�ѹ?x𓺛�Y"֣��Ū����(R1;��������/d��PV���Uֲ*\������avg��A\c�0�xrۄ�=���T�>O*��A�J�>�]��V�Uwe��2c�t�����9��=���+��Bc��Ի

�F��w�mP�W �Ȍ��L�e�!ce}ą��Ҭ����,VQVk��.u���F�(��T��sP�������������)J�<�r'Ww�j/�ƕ	ߣTj��xqG��Z[|���D�Ixu=1�+X�����\�J.%���
��du&~� �~�;�<Q4��xe�����h��ů��f��=��w��F�{p����Ux+u��sJ�\�h

i�۫@���+�����#HM��N<� f[����.<V�I���&W���}ѥ�3�����.�6!H{CQ�/���WBs�:C�N��c�C�P�y����4h{�8z*5��9�iS�^�z.����9*�iH6V��S�cm����/���b���	 �K*+��;k�]��@��-�Ht���|7d���H�u�3E~�h��
"����GR��*�5����T2C�-2{#�(��ɚ�.
j��F��9�[/��M�C��8H҇� �F��bw�p��N��)J�=ő;�nt)c��|Mc�%���\g������e�]�R���� ��.\���X_M�;,���3�s�A�~�yby�Ѕ�5�A��b���:?3�3U�ކ�"�m�$it�8s��`X�K(�aN�����s\4�Q�F�	�{:��-�y�5�Y�;��~Vd�zHL��y���3'G�lV�瀪~�˵�3'�pQ�����M�EےF�g���S�>B�N�q�K}��k�����^����y|��37ɷ��{�߭���e��
�ԥ: �$ʽ�єG����=��Wt{s=t��f��(�8_TL�BV���3)���I�h�}��r[��Ϸ���.��Ӌa���P�Χ���ɳ���p�no����m��#1��d��#�l���OM�'�Ş��c&������������N�S�W��2G���kn(RD�+1ﬕ��z�4�:޴�zutp��ʘCA~?I����j��]�}K;`պ��T~V�>��
��.�?ja<�k�.T �8:ϗL&3-*��r������r���e�s�H+���e�YU�'k8��|�2��I_V�EM���&���2�}�U�櫱EB��z���l�n=��ش��#t��a��l�-+�Yvl��W��gĨuWC��� ~�
He�Zr�nU@Bˡ5@UR��3i��q[�H	�\R��%�s@�R2_�W_�����:֒ٯ|/���"{��:���?#�\jx����I�!�׭�� ���d���N�~0��et���'O��/O���ȏS!`���i��ݴKihs�Y�21ˉ��Ԫu��s<��@�@?�w��^��.{c���G0ESم�p�S���)�h��3��"{8��t\\h�lN��;M��4��A7}����&���ݲ��Vo�Kc���GB���'(�-m^���7�n�D�,�㎜X�2z�#��G�W+�t��#+�@�@�q'r��c�u������S�	�Y�9���m�3vG���\r��;Z�lj�,�vF�l�>��I��)HA�Fn����,��ֺk�ۅ�߸!�%�e z.q���<_����}�y��ڲ��/;�yr���i����<�0̶�ݘ����>C�7�k]���Ѝ��\�~�}�(	����ݔd[m�<~�_YXr�tpYe+����� �{l�g!�`�����a)(�`�QNX���ߚ]�K�$��x�l�j�;����ߝ���B��Ra�-���﫵��������@i��D�˔T������c��
���0�3+m���k|��h�֕D��`��h	.>�ixܲ��س��/�1Z̶%�b�������AB6+�S5�U�(�-�i`�{C�R�*O'��7��2�e���l�臩5�UI�Ԇ�7l�F��$ؙk��W������[��^c]�R#+�F��1�v�p0��xÝ���6��J� �1��8�a���'>]�E�k��8�����"+�8�n]�c�ş��r��S�iry9���m��0��c�5N!��-,��d�5��ٿ�}�]�Ͷ���#�H R�t����I�-*L�+|�Y�%�i���XJ������DKCJ��Q
(���&�f��}��'Z�+q_e^����W
��uv:���ʤ6��O�x�6t�6���_��w[r�O����owgی����,����~ur��Y_��γ��ӳ���N_�:<�o�z����ֹb���;G����>=s6�``��t���i=��\�:�����}X:��Ry4�Ig�E~���n)h��	^#�zv��񋣳>�Y�R���S�����A2"� D�8�Q�$L���0g���z���&������$�.����M�,��,��.J:� ߐ�"�`@��H byʫ�Et���Ab
U/V� EP���CBa����W�����]��F$�к�)Yy�kX��d	UL.�|�b.t��r~;P�z2�mn">���;�� �;
&�c�6]�k��N'qGPn��Թ
F� ��g�����h��<������]Lá����=���y�(@�4�1E�:4#�%n�i#�}0�[���+�w �s��u=�@�z��-��80m�b��A�K����TCn�PAE�����N�S��g��{�V�a�Q�1�������cJ�r��髃����E�v0Z~�:����AG��$�^����m<�ƀ��+�ޒ{��L��ŧ�:�҃(��: 98��h&
Ӕ}¼��'�2V�𐈲3@u�gr�C��C@?����M�WN���ϧ/�{�Q[�6�Ć;v��)j\��sA}�a:LoFn*&�&G�l���� �Eo���3f+m�gǯ>�IfBt�T0&��}�s��b������.7H���_����%�H	��ĸ�G���ؽr��Lx��pЮ�N¤c��C���RC0�&�F�g�8�J�.��)qI.s�)^ J�Kʘ.N:�d���PƬз�?h��dE�#A4��I@�����K�缁�9��� ���5��L��)*���	�8�O�����ɿ�֣�6�+���輡]ց�I������p^�;d��x��֣hˍ*}���+�Y���(���"�׮��q^��x���̘Q������8"��ѕ�5A^��o^��i
�7:$��x�O�>����-yc�-Z<i2�L2vwA�t����":��/`�c��"���E�8#.��`@��ΫK�l��|N�$�c�G$���;����a5�ob�/��H ����B���e��٢��⥘o�y��嬑o�T����d�w����*��i�������ݥ�g������"��I[ԕ�֣$�I�\�yv�+�46����(e��@.~ޠ�X�`��n���M9?Z�$0�PWN���*�@�Y�ǚ�F8`�T#,�l�{lG<�h@Bo+��pQ#�&�~H ���������^>	Y��JI�������c�-��R�R�]�n�B�s8�)�l�q�z. U�*[ �U_]Y�uՇu��Mt+c����o��/ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ,ʢ4/���+�  