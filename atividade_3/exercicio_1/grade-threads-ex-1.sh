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
�      �<�V�ȲyEG��dl��-�3��5r�9�`����ڱ%�$����~���	��S��%�d ����^	�����]��7G4�N���/<�f�iuy�������A}qiyq����RP�7�j���c)I�0rB8���ᦕ���(n����7��o��������m���U{c���wK�Nk���b��W��V���/N���y�p�z�N�/�=�|�{ض����g��;���z����(q=2�K�t�!n��YB��R#'M��e��*Ћ<gȫ�'"ƬJ°*L����q���Z^��N�gx�:A�T�G�\���}@��r��*p���=
/tR�ͅ��{�-�����%��-јj��z��+�{�������7{[��=n����vI��#\���8,�"�g�~�T?mV��'e��f?K�����<���I�:>��������mc7�S��M"�2��`��@��Ry2���w��I�>�G�������ꓔ��������F�Gc����f���F����"���zgM����D�����^�]�/���ދ�٥��Vk���֯��%�>���H+s��$Y���x0`A��C�Y�SF ���e��s�*|?d#ƀxO�5��5�f�"<�x�ᗿ>���!��Q��pD���d�!��w���y���2���%��T���J�K�ۜᇠUQJ���j�ޅ�է��������F�Σ��KH�e�b��� Y�����Ǧ�cq��WV����N�j����-{�M�E ����F��"��'�1����þr��u֏���8b��	�O����Gӣ�{�t�aR���WA�&t����q.mB�#��x�l�3
�����9җ��� 'h��܀�R<9�Q���z1-����^��ٻ��Y ^��ꃳ1~�嗙�����"4��;�L�G��]��>u��m��H\���<o@�q�1�o�m3��pn�4%�\ݲ$�I�~_;)�Mc�� 2�(�	�4���U	eY�4���(��.K�`�g�@���M�ʶ޽>�I_����_�Ԅ��:�
�*7[)��$Ԣ�|
x1̓����A�@j7��c̺�%�jqlA��Ƅ�L1��4�2�J|��rcGJ�|��K���)�IN����^�y� ��(p��G��G�ޱQ!�ҥaq+5f��hj��7b�ACD�����) b�0uɭ<eaì)� ���Å��Zma��G� )G��㔌����u"?��y��[������R���X���/7���w�fܞץ=b���������?�ۭ������K��m�f���͇(͸^g0��Su��l����s�t��A�����ѩ�zn�H��e�F�Y���4xJ���J?���B���s�f��� �> L7d�9�!Fa�!�Z�^������9	�F:�Za�Ν�ӷ�F(���3�[�*��?23�A����� b��G@����6xT�Qdr[�v��3��;/�HC���0r�&��B�EL׀��e_b\�$�+�A���CĮ��
1J#;�M�5S�*C�ڡ3�d��D���8�PPU�Ͼ�@sB�`�ٝ�;��e�n��BU��Se�Hh&6�9AH�kUTU��ڨ��4Z�L?��l�8Ŵ?�J'�		g�e��E�.�\�S^��o'���[�Q<�חWW&������.R�0�`�Qv4�`r����<^:Tg��{.�N�����y.��I�ڈ��p��4���ۇǫ��C���J��"N)�Ñ���{č0P�k0���ì�M8"��bgo��Cl@���(0/	UH�ҡ�ڇ�w��ͭ�ɩ=Q�͞���>�=̭=��F�Q�(�0c�j�Q����0��hGEjH���/O{ovw���F��yr5sՒ�1���$c��s��T�.F���>��c,��#�ߜ�Du�BSlN����I�rS�t��"6SߩbF9�t@쏨���5�SL}|9��ሬ��3 M����R���"s���Dϲ!��v��������C9�2���;+a���/�B\�['\nV��� �R}�Dd=��%=b>ĪB�FP��q�'�&�|"���+$��.�i��e�y!�!��~l<
q�E�#�@aŇ���Z���De���P��Lk=�$�ː��^o�'t��
��p�I��� ����a8���Ή�	
�LjdMv�K�41��
�b��I�:?�f>	�
B�{���N-���	q�x{ �2��|(�Y(fU�B�Xڈ�:>�6˪�Sk��ƙ8/ȷ��A�t14G�: ��	y�N~<�~T�S"6k�]��2W��'�(��P��X$!BN��/����Z��@�<hMãD��H%��0N��X��QQ6�7�}t:0SS�Hw��B����%[PV~m�&I���40�����F��ghE�1cDD$)P�N�J0��bYq�!���Z�fQH�!5���FWsn��9��R�\�~bW�����3\�9�Y�$�OQ�f u���0ͧfe�e>�O�S����G��r����Uȅs�S�Wz��L��z�j��HZ�f���3!��ņ�W�{������
&����`����v>�]3�CN2Ana�/G:�?.y�P (X�SA2�64	ـ�8�n�/�a���&�:IZp7B���:e�Zu��Ұ�jJi>�4�^R�6�NT�
���t��ɹ�NҺT+k��+��#M��� ,MJ�}��ל��g��f5�5�O�fa<FI�b���1�#Oo��_n�N#���<�e��6�{@	�,Ro��[�v��l�9ĪMmEv$wW��::�����}�(dzu=��� ��C�[�k��M�9�#z��؟�%�Fh��7w��*�	(V��fۭ�WP�X�7���"��� �P��T
�7P*'����n|�B�}E�)��qxn���VjV�9�Ҕst#~I���}�?�wLW(W�7��l�]Pү;l��eB֔�c��g5��U���������	���'��h�/.bd4ߨW��|}���<e�F�I�,ͯ>Y��r�����U|ԗ����Z �.���d����'����W��������S�Xn\j���i;��s'�L�����Z����]��D�#t�8a �!�R�?i���&���,^b�8٘�<x��h��9�aaO89rOU(Y��La�WF��{䟛)�` r�N�m�1�E�.01�u�DT�PfE�U��I�r�3k��	Ձr% �a����b a5���~��+�-o�q�[�Wۼ]��Q���I��;��hd]���`�@�t�	V�
n�$>�`+N�H#��>O7��͞E��I������'�U?QHgW2�?�U�����%Mf�j�HX�vHˆIL�qA��e�l`�v�@]*@����2{�Jf�Y5"��&��&&ݣ�u�X15U1Z.�'�R�����:3%d2�c���H�� Ԅں��E����t��Ɇ���1N9����2q�sq�����$���x�0��W
�����dw��m&�b�rH��]a�p�mt������Y��|��:��G	�3j�S�=|��׀q�5+dH!࿰� ���t����t�|�]K��b'=z���M��0�C8�]c�
�������� z���{���r�j9��XS�.Wc5�k�`�CtԸj�	�*n�����P������|�[$��>��Nb�K@MDTqK��K��p]֚��{��N�.�����&�:uB6Рݎ��v�U/�:�c���<�;�P`�f�;�L��z�f�lT��'�cp�ޘNS�5�I�� Ңbs�ta�m�(��8ݬ��z��L�~۞f�U���m�,M03C��Gu��퓏��O���S��Rc���"���}����٦�D�I����u\WD͡���q���_��Ð֡a��_�x>y�t��v���j����õ�Ys���x�b���[���硽�N���u�cۧ����jh���J��n���!��V�F4>��O��4�2Y�,��Ș�X�0�d����"�ˮ'�t�9���������#��K�8)���j�!�:�>q+���U���JY�u-�[[W��v�b����G�	��-2p��4��Z����O���y[+mkU�����t��n���y�|]�o������Ö�n�uk���b��?�ygoه�o�Z�Z�I���d�i�#Ⱦ�"o{��T��oi�?������������������n�<hmn�N��rvښ<�P]3c��!�fB�(LW��:���a�����%QR����o��t�e��Fř.P�55�k�N+K"0Ύ���ز�<4̎И�d=u�0��6s�Ԏ,��8/��଼ �ʸTX^� �~�(H��4�%@�p:fm�9����d.��?�`��
�)���;b�Sn�g	I�;�\��d'*��`'r�g �{K���TSBi@B*��#$������r�Jﲀ������33�
��SIX��5�
�P��B��
O�Z,X
�L T&Pt-<!;�\�����}6C��&�Jy��T����)���Z��;������˫�������N���S<bʈ��:�ͮ�鮂��	���0�N�}�������>�������9?�,p�*���nY��d��v�A�~�I._���Ǟ8�&ݯ(jj�ЉA+
s�Z"n�2ǟ������|���բr�4Q!q�'U~�r��T�|r�	�")_N=�T���P����el2�pȜ�S@��q��+��ɖ~O/�(9��n'�4�i�O4��:r{���z�n��@���u�d�|����x��Y>�%�� ��!�h�C3蠟��YSR���ׯw[0�@PY���{^�ڔ$2߽�<��/+��%`�3(1�g)�	�8I����{Ȉ�����v�A{w����������6��Z�?�������F�G!;��I�����r3�;�'B�0����x��ʑ �H�0��7�q�xaw����\����Ł�kK~�kx����.�BB��\�G\�TזOy <M"�*�;��5�8xŃ��MK�NX�O9�1��ر�Y2fa�'���L=��%�r($�3x�a���]����X���eJ� L v��ݒ�iH����b�2U[��mH�EȮ%´N�m�ۉ*�\���No�.���s���\b��;p-(ߐm��^��
n=\��e��DV�nn'��)�V�y����YP.b[Y��A�*�܀1�K�V�q�Q���"t��8�!]�J�Ift�0�b�8�f��H�0Sy�2c�8�1-#�F�u�7�Rm|�![7��Ue�y�mj��Pv��b���V���`���%;��[����Oŗ�Y����2y��
QK&wH�s�Suu�n"�fM��&c��v����1)@����EYW�^�\����+ �*�
�����WsZVtcL.`�U�^�G�#�􏹰��+v"�x9%����:}�y��Rkè�V�,�K"�nU�L��۱�����|c��C�ꆺt�ƛ��#�~���ɣ�����d��8w�>c�<�ℝ�F��J�f*��r��ɢ���,����[���@���*6�X��SQ)0^�}�~���|_�=��-}��ZL��,T��H9�zŨ0ݰ��HQ:D!���1Ó��n=�u�hea��EM����� �qHį�#�[�I�<�������k�&�	�\�������1�����_���a�`��m��I7���UǱ}q4�f���i6զv��X��|�<7V���˿�2���_]��x�� G��}�r:vR�]gV���'cӊ ��o7���&�\�)��C�(e����S���U�]�]9��u��ŤO��g����kn�H�Y�#FV�
II��T�K{���ӕ�,;��TV��� � �d�Տ��֦�R�r��c��3��d�6KԮ#����������z�˩@������_�>Z��$�m�RKv&�MK��vJt�Mٟ�>y����f6uO8ϧ�����M�C�nu��\XΞ*��$5��B��v���k�6�78�h���Iu��6�&�d���F�*\�����s�qi�U��j��{�{,C���o+P��;~E�k�p��AK�U��@�JyL�o��O�x�����go^�}�\Hm�u��SѦ�F ��KM�i��8����<K�� MK]��>x,i�J=Rx�:Z��zUTK�|��Q��b(�����Ø��i��z����VL]<-V�8^4�
�f��/����)��c�-��I��b�=�htNe+Ľ8�����i�4U�g�+em(�2�3��UAl��yD�����,ҹy��mNY�k]��K�Z�O�r�_NOQ���!~�}�jt"���L����,4��6�Vi��4[/���ݏE��t)�<N0�O�1R�!��"��e�"	K�[mK�x_`z���A�����rk�� ¼1|*��cw/37�1��/�#�ک`!�b��B��S�NQ�Ԉ.ųG�fY�ή�"�O���&Aի	�d�깘�h/�L(#�X�^A��fB
M��Dޏշ�.���j�3���,�t���*9�?�1�@��U.iP�r7TH�7K���*^G��a&͞ȳ�Y(�l޹D$i,�����Z�v��f�f\_]jc^�r�:��bͬ�n���]�����*����7kT��-�qu�U��a?�9� F����KF1���B=����
�|?�B�;G��\{��K��Sgh�hԫl��^�d./t�v�U���t�9^���9��j5��u����-�D���}�>@k�lah��d�(=�2�����R�����
[=���������&L�h+jEi��
�KfK(�Ԛ[�>��<W�FjK�J�n��.�9����� �XZ)&�b<����@uX��=-��� ���f͘����Wn(��~Q��P�E�u��l��Ҙ�PW�vj$�Y�EQ�,��r�AfԢ�% ��gKM�G�[�0Iq����v�(=1�ұ���*�����ܱ��ދfj4�Q3�����&�2#�Rd^���17Е�hS{,�Ŕ3,����I0*5�^�S��s)ܿ6nz���<�a�IS5U.}L̵N�0߀^	ڭ�f��f�-*�ؖJ&��S���7/������*�??�Tb��r�� ����čK ����4�t�QT��9�x~�:fi㩻7���u��|�cx������q����!<��X	�����Fیa�R�����̡�����Q�)#��c$��L#�J�i�I_�k�5���;q�긮��vs����x����aO.�m2���Ǆ[�
��5Z��a6��������7��s}L0&l/`�0���!L���w�& %mT �����
7C��(�Fym�b/my�BQS Հ�(%�Ja��G�V�j�rb��y
�:��s��R�_�V��e�bN�_���
��Y�Qڵ	�Z����/�F,U�K���h,pq
���[������W��{ކ3>nE9(���ꑙ����$���Ӹ�"_Uy��:�~�8���X�pu�z�`�zV����z�j]����G��S��1p�O:$m>ĳ��P-eIQ�f5ֱ���Ym(��>����\J$s�A2�&�4a ?���u@��j_�G��.��Am�����oC�2x��^麐)�O��r�c1?t_�&VρE���� +��*|��p'1��l�x��#<���n��7wB-�[�D!;K��!wւ#J;k��*�-[0��٫�mi��{cw԰L+�����O-�~E(b��˚w���V&m6=���ƭh4 nߗ-W��Y3=h���q�P���Z6�,�"\)��R�
�{##�{�d��1{�������7�s��Fl{���Ny.���P�%;T��xQ�δ��?.�K`�;���_}s$�iG��p�U*ߕ����S����/��x�`��J���q-n(�2��`M?�J�+�Ҹ�����������x���%��ƺR�+a��`6W���-����]6zV�R�xOm��9��c�GR���T���T���/ dϖM2�֥�Y�_׶[fo���i��E�f��x�[��t�	�~�|��ܵ��S�aW~�fV^�k�b����p/���;I��<�
oImY$�.�ɜ���C������ǜjA�fI|� ��5���i�â�BW��n��W�b��W?���Ks�d�⡌�V{-�qɭ��mS\,7�ռ-%O��~���K�7� �y�Yk 5sK�D�p�%��#K��*<v^3��u�ͥ�OՁ��&�^4���6�u=��.�z�Vۿ��
ŝF�4�6.u����f˻�+���g�E֭rs��I�^��,WW6lJ�[3���6�j?��dKS��Ri�zgVnD�(Ԫ��:�U��U�<�umz������ߋ���c�����݇f���_>\����������<8��F+��l���5iܫ�fs/��o�ta�c���.(��2��E�kѬ�z k����b���d-z�\d+/�U�c���>�֢���l�Um1�-6	Sq憧'���	�S�h��L�t��r6B���hTw�L��|�[@f�n�����>���)J�_i�E�%�O*,�����l�J	^j�'�k_0����u����[�Lnk�N-
c�ì�e�M&��]�e�z�����������G{������Z�?�S{%���孯Z��qe��(�#��sHPRk��$���3	/��⍥�LG߬�ի�R!9[� ��i]g�#@<'_���E�Юd�Of���c��}+��_P�0K��0�y�4�H��n�W�[�َ=�n��.7W�O~�x�#CC� ��3��:�z2�b�߇?������\	�j��[����屫]�l B�����_���W�
�:�VZ���}-������
w��(z==��Ѥ�t����^�1;,|Dy"�b��sZ�?��?��}����,,��\L �X	}��%�5��J{���x9.vC�2
��Qw9SGd6|�M�>��SR��:�5<3{����ܖ���]�]���y�%5�P�o�����O���t�x����Ѡ��=�r�������O�<����קcy�\����lp���g�.���i�Ћ:�o^��y=ǐ΋�?��IĜ��_}��tO�<M�[:s�֧0�T_�"��,q� �����M����8eC�����P
Jh�,p5d/��<	i h���E����<�cl��Zb#�$�N�@�hlN\qDK!XC7 ��L`� �����	(���g:��_7�Β���o~a�'�����]�+t�`{c(K`������A�.3��i���_����m�g�� �B N������ۮ�p�^��l�����4H\��$9�{��m��^�<�N��_��,���[��>'��N��X'��e��C\ ����O>ot��<7���Ѓ`D� ę��{�qC�oT���N�iJ�d.�r�JY���3�s�����}Gg��lDuc��W�G�?��G����W}����������t2s�iv������`�b� �#�B�V�O�a������z���� �T��<
���x��������!cE��� ��<��]bX�F�q�ُ�;�hT=gx�_���y�Q{�>��gȰ3�"$S7�ڲ4����XL�/K4�ltӫ Z��V�`�6��q�G�z��ɶ,���d�R!��	�0"'w������!MD���ZR�K~�����WP�`�^�|b&�D�+��|&�nI���RC0��zf�0N��v��'#n!)�eU��ZC	�����LF���
c���V
yAD8D������W��D���
�sxo~A��������'��nt~��;�GqZ ����!��߾���~e����ț�ҹ?�vw�8��8/��1I�E6�P�O�7���8�<P��{ s~���4�K�k0	ɂ%��_G㈢�ڥ�^��߽:8�i
u&���1�]��/�1n�_��=y3�-Z<i2�$�̅%e�fx���1��=;��	��x�<�nS���	0 ���yuA�����%��Y�c�]Ŭ�̝D�?ưٷ�˗d`$@��o�z�خ�=������A�����/�<L�������oo> ������^�s1��3����.\�^��"�f.;�$sR����%pM"䊆�ӛ_�ME .�i��<� ])�T����j�|���M9?S�S	�+'�p�t]�aB6B��R������g#�x �7င�Vj7�FvM�7
��0 b���gG�oN��IȜV+%�2�7_[+����2H�B]d:/��o~�D��q�S��.�(`�9bPի�RY�Օ5_W}XW�ݔ��,����֊���)���az?��Ń��/�����;_����x$���}���m��0ˮ�^���H�BFy�H�ò�wЋ6��A�8���]M��U����"����Z!�E�3������`�w��݁�P�p�9��o�)U����.Q�{a�:��ʭl)�`큢ߺ!�����ò�˒�U��Nx��YW�k�#9��3�Of �s"�qI�s�	s0�02���P霳�"��x�(�Hd��5I��*[���0���0eئsrt8�X�r�Љ�m��3|��v�e:1e9DЛ؎QDh�zI��ϸ%��C�oʹ�����o�/��>����}Q���y�����){��⶧�9'U�;�h��V	;���r����t�'�xJi��A���<s<y�/z#-J��`)����wr�;�DC\�Cź���a�!|;}�����%��\.��3�A�ra�hc�5��ϳ��S�X^e˨�PV���٫lj�����A��G�b$�y�h3�@9:���78�Q}�c�.��ȰGjҏ�sX��R7f�;E�u�$�\!5�B ��q�Ľ���$�@{�=���������5s�%8�
#g��b0f��Bs,Z��FB�x�ܑ��]��5��\D�d�A�F�1 ��ܶ���Ztc=l���ސu�t&�2�
�����0��0Ǘ���c*O|*ץ��r�=Ce/���J�EԜFФ���oq �zV��Y=�g���ճzV��Y=��?�����J �  