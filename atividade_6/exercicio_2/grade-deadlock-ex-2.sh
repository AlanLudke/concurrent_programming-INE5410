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
�ЎH�WKf(�-k(�Bz�3�x�D!>M���s��=��#������eGv�Rz��f�X��_���ڒ�h�R��_x�͞<������.�Է|��V���ՕƃZ��T[|@��K�3#' �3��0nZ������ �&�������t��w�d��<pF����D��ݒ�������������v;䋟�y��<\8u��S'��l��=l��wv[������z����s�����I�~��G��,!U����&��ԃ:BXE�3��̎cV%aX>����q���Z^��N�gx�:A�TqD�\���}@��qj�*p���=
?� ��W��=��*�wW|����o��T��ճ��X����]<��?������㶏>�Q
i�T[.1ߏ�òفi!�~f������ov������g����G�>)[�ǟ�`v���~|ܰmfv
|�Ide@�A�,��ov[*O���.�8���Hp�����{Z}�d��,p��z���јf�����oy�Q����xT��������mo��o���k��.����ދ�٥��Vk���֯��%>���L+K��$Y���x0`A��C�Y�SF ���e��s�*|?d#ƀxO�5��5�f�"<�x�ᗿ>���!��Q��pD���d�!��w���y���2���%��T���J�K�ۜᇠUQJ���j�ޅ�է��������F�Σ��KH��b��� Y����1Ʀ�cq��WV����N��K/6�[���6� �(�ߍR�E��O0 c8C	���}�!�lG�q�FƟ�CE���Gi���/¤pS����M��52[�\�>"��G@�� �ٚg�#?`�#r��9�AN����x=rF�*DM�"bZ�3�=k��ٳw�gͳ �H��gc���/333��5Dh��w��j��I���}�t���-���^��yހF��c���f$"� �ܬiJع�eI"�,��vR^�� �d�Q2R�iD%&�fͫʲ�eZ!�Q��]�J�9Ό��ۗ���m�{} �������-uX�5n0�RP�I�E���b
�Y���́�a­ǘuK�q���*����	q�b$iZe��"��*Ɓ�p��1�d	�S,�\$s��9�C��Q�zQ����c�B�K��Vj�����T��wb�ACD�����) b�0uɭ<eaì)� �_�Å��Zma��G� )G���'��?8��D~P�����B'��������:��_nܯ���q{^���m������f{��n���Z{[/헶]��j�7�4�z��<�Oa�u����F����E�c	���gG���O2�N�	�$�V���w�i�.������~2��7��&lm�xͮ?>�	�} �n��s�C�����jQzYPO���N��$��[��?:w�N����|c/t�<pn	��&��̠E�H
ڃ�9(���n?���QaE�)m��i��Δ��#M�c�a�vM��w���\V�w8p;�}�yM� \�M E�E4� v��� 3�(���7�L)��k��p4����g��,C[@U�?�.|�	郱gw���o��o��U�BpL��"����n�!��PU	#k�b*�h�+i��γY��b�*��c$8$�mV����8,�s]Ny�~���x���
��������29�/���w�N�Nfegs�'g��{�.�A�eСCu鲱�B�t�Љ����:�T���XGxL�8��}x���:d�)�D��� �T��<����G��żs��>��ڄ#��j!v�vڰ�`0��|���P��,
h}�zg�a������M���I�����3�n$E��~ +v��({���vT��4(���fw7Oi4�'W3W-ic�K27i�J��bDq���s);��l?����IT')4��4��IN
�M��e:f� �L}��a�H��?�^:�l�O19�!�����#�N:� x41.�VfJEB.�̑:�/@$zV�H���vF&`�-�ʉ8��`L��Y�8�e�}	b�n�p�Y&�@K�!��؛����
�3�j?0�#�<�6���0>=�!�uHsu,k������c�Q�i��� �F~h�끊22�]�?��R�eZ�&Y�HC��{�e�й�+��5'�R���oHЇ��.J;'^&D( �3��59l.u��xu*d�'������$�+��1�B:�~�ı��L��/V�XT�1c	h#.��`۬��jpL���WR༠܆U�u�T���H�T�'��:����Q�O��dd�!wU��\}��X�t?�B�Fb��9!���~���k�z�7 �ˠ4���"�p��8!�c! �DEٌ��`����JMm#�Q>#l���,��*��NM�8��i`���/����c�Њ$cƈ�HR����`@�Ŋ��
S�)T��MRH�!5���FWsn��9��R�\�E?�+q*���B��z�s�S�d6����g�P�L�|iV6Y�#��.9E��|��q��,Go9��B.���Tx�GI�4>��V+dF��>�`tf��a�-6]����o���lU0a%�L��,��1蚑�r��	r���<�\��)B�`�/M(��>��%d�ⰺ�����Sw����$���\`�{ �۔Uj�Ib,J��)���ҌzIc|��u�WU�ǧk7GL�uu�֥ڹ�Xӽ7��
�4qJvh �4)}4����9�3<�zSM6�u�O�na<FI�����1�#Oo��_n�A#���<Ǵuk�= ��t)�_��[lv��l�9ĦMmCv$wW��::��7�;���Q���z�wMAn'��Q� ��<<��24���D�uJ�?�J��*��7w��*�	(V�DͶ[��y�Zo�áD>�D��3���o�<TNFy��_��]Zd��11�8���E~R�[q�Ym�hP�KS�э�%�Wg���p4B�1]�\����g۸킒~�aS����,� ̞m�t�WٯbnP��cGG'l��/֟�/VH�1�����|�^!���U�Z���'�4��d_˵:�OW�U_Z���k X��X�ד��V����_�_y��^K�Ug�˫O�k�q��>B�����`1�{Vk-�.�w���J��	�t��ȆL�J�J�L��Y�b�8ٜ�2x��h��9�aaO89rOU�Y��La�WF��{䟛)�` rN�m�1�E�.01�u�DT�Pf'E6T��I�r�3���́r% �c����b a5P��~��+�-o�q�[�WۼC��Q���I��;��hd]���`�@�t�	6�
n�$��`'u����T��[��V�"�cI�ཚ��R�[����'
�l&�N��Xժ�k쿤�,��(���ꇴl��E7&�{]���j'�p�T
ƭ����U2;ͪ�I,6�4����Ab��T�h����� �%P��:3%d2c���H)� ԄֺɎE����t��Ɇ���1N9����2q�sq�����<��_�6a��@)g;U)��)�:L����!Y�7t���]��9��
v�Wd�c>E�}T<2�Ԧa&�Ψ}N���5_ơ���!���������c�4SЁ�v-;���`��9c'�9N�	��+T�nf�2zh����C��(b?�1ld�!�.�ú¾p)���ߪ����U�O�HTq#�Wo��Bv��lЏW�#�#9C��@�_j*( ���XjW0X�A�yYk���6)�`�2vP���	�b@�v;f��dּp��4���@�Oz �>b�|��4Z��̠���\��o�#��ij��9�����؜4CXo=�����Z�5�	�o��l��3ַ혥	ff�;��N��}�Q���>���CcJ�W_jL��[Ŀ�r�}�g�lӈv"��$tÈ���:��Qs���q�NH�/��aJ��0�� K<��r:Vi��nm�[���������W<�1�G��u����k�`��:ޱ�����Y~�Z%f�Rb ��6��uyR��F4>��O��4�2E�,��Ș�X�0�d����"Uʮ'�t�9�#?�?p�~@��7⍿���ۻ۠V������2kN�X�*�[)볮�A�bk�
�T,08����8�{��E���xUa��@��C�l��J�Z�m'8w=3��k�z�\��ۭ����e����k���د�w��[�������z�V{R{�;�p���o������)������z�kyu)������N���u��Aks;w��ֳ���!�����i�"Da����~��k3cO_�DI�*��#�Y��=4N��:g�B���r<�=:��D`���!���<4̎И�$�:�l��p��sjG��3�e'8+/��BS�� �ǈ�a��Y@��[D. �c��&�SIO$&s1��q��WHN����K�r���0�JH�ߙ8��:$��PA8ᐓ �81�[z,���JR)N!1,���Ė��Tz�5�>�x�֞�A@T؄�J�R��P@�z�~*]Txڈ�b�Rhf�2��k�	���暽2�
M:�1f�zk5�x��:�ct�4*����jU��S<������vnM���WK����q?��ţ���X�2cu��w��a��`�w§n'L�Sy8`�0���Ͻ*���#v���[@��1_�-K���º���8�4)��+�;��Gۤ�UM�:1iEa�QKĭ��B@���7�p>p������ZT�áϦA��
ш�>��K��(�/�_rsvJ
h�GS�9�?5��p(@gv�D16�8dΐ*��1�8�J˕�K�d���v����@��MXd�������^�i�ޱ{0;0jk4Y��Ƹf�-q��l��;��u�*ŕ����;����֔Tm{����,5TV%c������D�Pf4�F�}%f�,%���U������şܙ:h�nۻ����O������M<�����1�?�=���QȎ|r�kF��<D����s"xD�avN}~h��K� �$��u����;��Sy�ȿ��Ł�kK~�kx��q�.�BB��\�_�TזO� <M"0��Eә�8�����<�,+�(
��rd��ad�*�d1��,>N�'���z��K�PH�g��#<xU
�9!���i�2�
�˔�qA� ��;�ӐrAW�g�`u���s�ڐ��]K��i�ۜ7�?U(���]�\]�p�	��?��DV�;p-(ߐm�d/jw!�1ƲXn"�d7w�E���S/ݼ�d���y���Vx2hP%��2J���{P��q�+B�1-��ca�-�$�dF'c,f�������B��ze�qcZF0 �&� ��0o����&~C�n~۫����7��~�
��ѭ4�o�N�qKv��Z��[�O��,�b'�r��~`��%��;$���%��s��H�YD�	Ř k]�~��'O
�|} x�EQ���;Wi���
ȿ����6����iNˊn��̺�\����|D��1V�2�e�N��S�Y%�����{��O�8�Q��
Y|�D>��V����c'��<�j�����V7ԄZoji�D`��{$ޕ$�F��������n�g,�G]\���\0�Q��
k��ma���3`��t��%�p:}�dņ/��9�� ���������ꑘ�.!Z�Rha2Q���`�BD�I��+F���Q�e@�3<	���s['�V6�`^�4h��y��D�9�5�������;{[�a7�M�tUfثf'�/c4[/[[��ۭ����?Z��nH��X����([�����T�z8�>8"����yn0�
�������_]��x�� G��}�rfvR�hV����iE���7���v[����'��C�(%�ţ�)L��*����:������9n�gϯ�Y5�fF#�Jn���ZI��J�}8{�rTII���	ə$����%y��T�S�^�U� 	���H���TْH�4��Fw#�\���u��6�n���N��k�b��;1�w�� �L�w���Kb��\���#W�>oyP��t�쟜��ӂ�esF��ŉ��4�HnHR��=/����^K��?��G�C|.��؈JN���6��pA�����j���|�t��)u�CẠ������T(X��%�*4��n �R����\D(5<�o�xo���d�͞�ڨ�7%�E�EoDg�s��?� N�(`4���Ћ�B�'��@�f�T#�C�ђ�d��Z�~)��~�ߨ��
�j�jee7d�{l�� ��6:Sϳ���� �X<����9ڶ,e��:W�x���}�D� ����=]�
Q/�J�E���j���s�r9dR�ȤyS�� ��l��W8\��"���� Rs�<�<E���TJ|b���bҊ����������\#���+eZg�I��D�dl��2	<[fs����X �L�b����y!�\.C�^/�6I�"�i*�ⓁI��ﲨU�_��X�N� ���׏ݾۑ�yip�9�	7��%� $dП�4E�S#��EQ_��N��aVJ^�E�:��˲1�̽��x@�	�J�4m&$Д�L�Y��RkX(��f��"���n-���r�J��iL�P&l�STʜ�s"$��-@�l�#��0��%�oj�|���"R7�����Z|m��ɸ�s)Ul��5�]j@1�N���]�gVn�9��D�0�*�T�כ1V|j��o\�2�2l'#&��h��)c*|�rL=(���X�>�Lҹ@��B{��C��SWH�h	�)�ϙ�U���p�1�eUӁ��D|�q�W��r�!�FPӵY%�iPoLA&ґ�k��� ��jFN"�J��P4a�-9��%���ƤK�[�*78[��3ߧ����[�����)s(!5&�ZHƲXM��q�mS����=��R�S���R
���btJ�@+��T�G�p(6R��lҧc$峴X1�lzt	���K�
�yX�i�c괈���.喍PWs��N�/8��A�ES���Є�����CL���K�G�[�0u�8�g �{�=c��Xǂ���_��d4Hm��x=�5�Я�5�Q?L=���$�Tȹ��cP���@fu6�"X��jRs`�jLB���X�9{#�k�7��Tn�Ҽ������}�Q�VJ��5T�0:��4�q��c|R,��B��F�%��X�
�g@��gJ��򣆲S~^��}�7�V�CގǓGN��B���9f��R�5��瘬"�&~�SQC�(_ş*N��s��w0���-Ar�G�ahF����l�|�f6eN�:qhi��a�	�_O1�E��[T)��z�OE5��I�r/�Q��Uu�..�5��j����e�I�]X���kC!:&G[�<:�Ӏ��LHG�h��[��1T�]Lr�GlN@M&�����$�'v�$�:@/��;��
����yukf C���)���Ն�=d_
��z�Ւ'��Y��b�q�S9��F�<�ry�;�e*��Z��O� 
.5�_���
2�I���5	̚n���o��ȭ��.����c��;�p�x��&X������t��;�ǭ�6�X<���i, ��Yx��T�"O�VFҏ2��1���nC ��g�5*��U����kI�>��q�n8������#��#CNr����"��F:�S5b�Ŧtه#�j�r	��n�dm�p���������* V�y�/3$~p�0�֠�6D�t�y��c^k�t�����\%��ݳ����΢T�Z|<���*����2�B��YG���O6bহ��ׄව��w��|p�ԬE4k��Jb;���*���~a���W�@���5T?|��l�%���/������H�4qt�O��I|5�Z(����y�MY����g��lV���`�5�9��N�_��}(0�^Y�l��*7}4O�k��������ݣ����c���P��!��Ԑ2�5$�� �&3�}|�փ�?�L���s����r{��!�T��ل���7�P���Nh���)�]+� �a�=�&1�ʥ|G�8�fw-���h�y��R�+��D\O��7O�}]���7���c�ϥ�\�>��-Q�W|��9�[L�Y��U��d��9ù�/���\��g�|�f��GJ)0��BtB�l�+U��*��ޜ��m�x��f�.C��b4�?��������#\��{�4�k��4î`��學��1��q��#~��=�Gx�p��	'x� ���Zǲ�m]ڃ�b��1E���ߡ�y�1E�U�j1x�0�z�^�v�i��z-.Tvns��P�a�oS���j�E�"n�%�iZ��"AMa)�=F���:�N)�4�IJ��G5�B`�8)�I(q1&��#sӟ���x�����`�����{���]Պf�36�䬤������}O�*�7�{q�Q���cF|����y���~��&k��FV�X���Kt���¦|~GcF�I�W�)Ւ�4�RR����B�(_-��TdO���T�t��3����1��C�Aڨ����Z���t������?�/���~]~�VCO�?�/*����G���ޏ�6?1D���&�^��^�H�`d���Z��b3`���yzN@YA��+VYJ�p�Nk����z��=��"��~,�;��
Ԅ�=���T�<O"���1
�hv�%�ڬ�[(uX?w.]f;�@!�4-�=���S<�҈o4�hM}� �tϿ�i�*��`Kf���`�-CRR�g\X{�ʰ,�lQ�bf�&��Q���m4��K���07 ���O֟�����~���Ry%���՝����qg��ȕZ��Q��#BN�m>�2�Yg�_]'9uk�q��#��w	�K	�l��(ƹ9Y��_r� �q�;�>S$��x��	`x����em���7(J�k��1|��$�̃K�o/�[)[tX�*Ar��)0�]n��Oz���c�}�g�A����i�ȳr�l��~����c՟��Kr|��]�0;��aM�]���"j�/a(��e8�J�b&S�ݽ��q��P9Um^�ÖB��	��(,KO�&����)W/-��/��a���grV�!�\�_��_���[�|3_YL:��1�xbHe%�ykI��?3P�}M}$��íL2�Qp���͉";X4�S��Z^�3��{�掉��T2C�-{#Z��ɤ�9
͓����5�{o��I�C��ȋ⇺ �N���x��������)J�=Ł�\7���Ʌ�w����%����	�bG����n<�d)I_�E��&�`���uk~�K矔i������ft8��VX�s�a�!�!l�G���b�i-<BH�yOۆL����o��-���V���Ҁ�s>�����u�W���U��K�Ix�
!����S����n8�x�*�]���2���F.��q<�n��:������������������ɋ��Ý��ke�ח���
;���&���#{��A��Y:���?U&W�����:rU�����'��=�����Q(@����*/up-P�:�i��mlo� B1V]~�Ľd���@����&�diCBP����1)�E�$���
�^7.+P ?�X�0Q�t�O?��
��nb��<'�w|l)n]�X�&�H�� 6�-@��"�gÑղ~KR^��.{����ԛski�Cx�7h'�'��9;��<��d�e�;�7�"�f	:aK�);k�c�
$�0��|��qȖ��=J~�\���D��5���u��[8�x��J�ǽ�ȹ���Z���`���=�)�J�����j�p�O�E[}��X������Q���9D s�l ���z�/�^/~�S�������z����_�"'�=]��L��峹��ra��-�H�y�uؕ$�(�>ba`�{���\���	K3���~��鷣���g�[�a �gl���p<෭��Nx�����sz���>Ԥ�����o�(}4��?�c�G��-g�^A�xk,[�-�^���}6��
0�Ktʌ[���x�#`?og�cm9 $۔&�\{(�H�-!9O:���0�l�=������[�>�#�"�e��_b��}��H�-�^��n-̉^r�tq�e���{k��l�o�!��>��#>���b,&�8�0�_&v���M����%#�ko 4�P:�Zj�����y������')�zɉP��Ao���h��\��G����ZF��ۼAfLlL�?�I�;:<�>y<HZP��*ʲ���J|���~��������ث����_������=�}�����#�j4�V�/��+��P^)P]z��b��qJ�H�_
#�Jx&�(.�C�k�h�\���y��al_z��AZbfH2qx�r	ڂ�A�{k���@��@��c�d}��#��>�ݎl������8�n���(�u�Il���%����,ѐ1R4�~I�����0x��8ULo��`)�tѐb0���sgEծ<( O=�px�_7I�ΰ�7I؎�6�	�t�@z5S}"	ޓL��Ǫz���#"ѱ��`�����Ը#9�UAhdב���I�Ɍo��U<��ڋ�pp�1wB"g	���*1%f��O>O��҆��=���>f��k�����DѶ��%��~��(��0;]��!}[W!�����[���M�l��]~�#��:w�|M~�ecS�V�MJ>�B�`����M��GK��?��jPNV�E�@�P��I�4"f���#G���Y�%�\`5�*�)���v�v�20�F;����[ҙS��!�}�6j�����������'�3��S���v��/s.��Ö�0����u�!�d�CӖ�V�	��j>$��!����	���/�= �R����9#����2O�����J�XY�
�X�҅򌉯����Nͳk�_��8��u�Ƕ���5�(�x� �� ��Px�n�1��l�ă���}G:ay�Hz��4h����è�z0	����C\�#�:�n�+޼�E����q�߻d�_ZK�����t�h�y:������`��ɖ4Ȱ���룓������m���?����[�_x߱�B����|�:������z�A�~ͺ�����{[ ,FxQ��h̓{n�8J�@�CK?)h��^���{��w��6���B�#��E�x _�Y�nl���s1��z�p]����+\�؁\D^7���þ����n�P�m�>�`KE���>�-2&�B���ztBc�z	�P� ��˝�:�%����_��7$
l���1��:� �#�H��b�P �j���-�3����mA��$m��`z��vcǇn���KVF6z�����ݮ=N®�����{����c����b�^��N�ի]��5�{�.���]YXꝺ|�{��fx��F�����q3����-N�'[���cG.[�90�����n8V<��N�S<�G!"a�#�!5h]�}�����A�#���.��$W�i�Yw1�v�W��'�#Jٳ���x��g)8w�̖뵎���'0�����8a��׼�ǽ�/�
]oI�hG޵��[Pz�ދ�s�"g�:�	�8��>q�{P0e�����#e��$����m"XL������Fe�z��vt�_،�
�AGlH�#;F��u ��q�6�Ƿ� �#J�$@��1�3����-���v��->�Yz�h	��aT�!?��+� d�����E'{[[�'����%�H�6ļ�G���Ⱦ��<x������G-���J�7�R���� �'TQ�c_��Z��p�C�H�А��_���p�q"�����
c[��ViAV�~���B�F�i�o]��R�9��s���_����5�����<�*�����6$:��m���Ji�����m=Zh���W8ݯ�_�u���rVW�8�[���]:��:0�֣`ۍ�}���W<	��5ԇY�/�EF�={@�n�A7��\��M��QD�ͣ+�i�ym�~u����)|3�t��m�&�1.|��`O����N���<i1��<����������"����a�p�Äox6�C�J�����uuI�����%���/t�=�c��oC؍{�M���%	����� a���4��*�41��V3~�z����7xT����t�o������e�����/�ݥ��<0�?���ω[4��֣( ��_�yr��4F�?���m�c@�7PW�i�[��$�����h�9A~)v�� ί�F�5I$#����Q/�t�lg��p@L/��ڎ8�I5>佁���`��{;�Gg'�"d�F;%�2�;W�+����ҋ�Jm$:ԭor��pg���$�]�1nP@�	bP���R��՝5�W]�W/��ë�����&�{K�2+�2+�2+�2+�2+�2+�2+�2+�2+�2+�2+�2+�2+�2+�2+�2+ӕ����[  