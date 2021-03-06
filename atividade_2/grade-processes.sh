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
�      �;	tU��Q��0|e�+�JK�CzϢ		�$��$�E�th*��I��:	Y>�踌��"(*��0.��8"���0��E���"�(�c�WKW��Nd�?��	]��}w{��w�{��Jr����}~�怖���������8�i鎌�L�����Js������h�H2#"ԇ	�M�tv�����6Y_Y��b�}���i�������(2ak ��dN�{Iܞ�?����ii}��wȟ����?i�����5�TGM-˛2���;�xRa��I�+.+��qRAD.�"�G�1��/PqT�LY�9ȁ���\��0��V�3!e���Ȉ6I�n��N@tUqIaz��Q��3��EƊ-2��Ȥ# !f�V'���6@���6(��]���"������s�/���������p\��ь�?��$����D�}\������C�d���H)fl�e4y�b��y�ޔ��n1�h(�ȸ�c���R�b�xZp����8=�׋����Fڠ�2�n���^K�x3��ȓyfk�L�����<&O������h����"�g��'����?3�{����r^��ь�?�� �~Aᤊ<�����%9&����TZ2>ǔF�+,,��?1ǔNa�AVvZ��F��H���;	I�)��邉��2 )Ȳad"��5,!+�?(Wǀ��@h���֐��h�%��"HR��6�d.�
9�R��/��I(Ba!�l6��J䏦,�X�i=9/�5�+���V�̲��UM gs0�z��lD.����i�d�T�� �E:z�K��@�b�ZV����]�8���H������_�WP�-�� �jeʻ��H�om��hCү�dN�p�N���#2)�l�?#���	������>&7V�|�WJL-��L�K����ȋ�J���%5OXH
�*T�x�����G��H-+[!k�Y^Ffj����K��rL�Z�����=f̘��$�3�\��}��5����ς�:���h� �h�U���+�rD���2�1�H�٬��tZ,�x�ffU�d�Ā��B��) {"�a��d�U��X�e�9�%���6�C��n6@M-�ål�)eP���6��c
Z�r@`�0d���劇r��v� ��`V@w��F��f�xm�h�V��u����ƉK��K+�$�H�cC�r9b�"I6']&�HVbX��ɂ�����r y��m���NE�RmQ��6���٘3e�0� ,1d���|B��D��WW!/��0�ɬ� lZJy��%���p�������}گ�����9?#�6���i���������t���Ҍ��Ϗl6�ƅ˪��u��8&��F�G�F��P�b��2اQ3+
��:��SH�S ��&@�1��b�#hN�E��|uL����P0RK�cEY�l+�8'x��g���m���akS�hu��;*:]������ȁ�20`�2� lh��a�L���+q4	*S���M��M7V�1|�$���m�:�5cċB�MNd.=�[�D�	A,D�AaFd��aOT8&��9�r�2�a�ՋL��S�X��1L�{�)w,S�݃C1j	!�Q����J��^_u��>�<�.nlqK�6��GP����5�4�Ҵe��8�c�])E�vs�t]_��\X:.��z���?n��O�`kE��?n��O�`�"�ɫ��<&S���T�����M� )~���
�G!mx�q�͈ή3����q#\+��p�(:��(g:���
�|,0R�Յ���X���@X�B�P��C�(>�A��y�c#w]Ft���>E�d���p��zTB�J�D1��N�� 3�}���a�Cc�O��2���BT'"�HV����#�(4���6I�J0ʀ�!?�t5��(�L��?���b��Z��h/�8w����p�ǝ�9���ь�ROƔ�ω^A�2���k`Q�rWMRW^��,�uaF�C��dC#��TQ^���0oҔ��"|�O�������L|�@���V�q.+����$�����D.�ˡ�]c@ɤm>H2p�J�x_0�d�������qB�.��kq��2�����k}���SR�K�r�G:�<�tW9���~5���y��t�ؐ��f�;9R�dS� ��rr�S���r�b֎,��-O�*�ՖlT=�s��6���TS�����d�(h���NuTA�"t��4)�$U��YN��6u�����l��J�z�PҪPݴ�ӉИ�z8/.�>`��+}F�ɟZ��8����%�L7z�{������K��VF.��JGD�e�Ć��"!���F�n�<�H����6{��5��b`v*�l���3jh�:�p��ݔ���cq*^�ɱx�d���PIUKU���S���U���U�h
�m+
i��@D����IH�Ud�TieŔʊ�6�w�3ku$�P�CK3��݌U�~��26���[^ZY�_.�F#|��GvÍ~�n�j$!��%�Akrp%�4��(*���)%k���ٳQ|�ye�/�(X��D8������>e��@l
P`E��*�F�a<���Ru�r�ML�5�lK��=6������ag��,�͵ͭ5֦ͮf��b�{��6��*4ܽ��E�+�p9Ă0j���.�O9�M\؄��bk f ��
����f͵�H�;Dg�V�ȑ��,���-+-]w���]@h�ٗ/�2<0���e���7-��cF��8����lz��M(QtK��T�1%�:6�P#�Y�\���	\^���a�Qn��B`(0,$Fx��A�I�P�R�OĹ0�D��=��Hbl�>����(�gc�yB���Cv���PQ���9�c!�#W> ���[jRAc���Bn��A�V��14n����9��P@n�d%�Uց�	�KFXk� "��K�Aj�q^|ad#6LH3LS1>J�+�Wd�m����|A�Z�	��y�'�r�D��|6T����w�>e�?�@L��A�
���6��O�65��"p�T|
�K��� F@!A�+_F*>�������X��c���rF�#<t�%��V�lD�m��)��P�~�������ؚ�}Pa�H�A�=zA��cS�Z�&V��7�3��뼩�&��7�y�5 ����,��+� w�M�ߙ��ѕ�l^h��"���y�ΨF�
��,䒰%հ0��d���B��Y����'�1Qo08��`��� /��!��J*l<�q�v*0�n����o�WR4�#*B�Ew���O+�l-'[���V�h
A��_6;���&�Y��(��� ��L����N��/-O��ؒa?-���(��F�l�J��	�q*�J85�������J����¦0���hߠ��i4��e'����Ʋ	��|^�+����[
�su^��U�6P�?�@Ir@Rd��dj��M�:~w֏���@��e�:��x���cK�`��&�y�ɀ_��߯��W,H�n�0��S���pW������甊�{��]S�U##�:�/�3$,M��)��5QQK+��i���^��ڄ��U�e
�[�u~(��x��\�#����j-g�}���1_sQ��X�ތA,���+��ZlR�,"}Y8�)G�!�"n��{�4DE��&�����Rr���Q�n��I����r&%�~D9$fIס-��f	j3c����D���Z��17'��J@:E�Z�&˚�*�:u�S�I7��wR*%�S�E{�g�/V�k߉!�%[���G&�+���bU��Y��|WK�=ޖ���D0�1����N��D�N���r���ȴ���EC:�o���n��EG^kvLrL������3&y�>�Q��~�Ջ'l�3��}��۷~���/������Խ��_�Ur�e���'v��4�M��ꇥ�3O�?��^1�����7?s��!돏{��}���I�3cM����wʹ�����i���//������3?�Z$e�J��ř�B��ͪKv9��{߻gT��@�I:z�53V��U��w/�Y���2_��=w�ױ�5o���_����}�O�N<Q�~�D��U��w�|d���k��-�����vC���o�|0��72�K�]�~�E��2���u#o0]��/w8�t����Gt�:1`��qϋ?ݸ���&o޾}�W��z��ot������v�큡�;i�v5?��]O��r毋2�D�/_��o��/�#tN]����j�'��Q�������ݝk�+�<������+�۱�����i��R��o��}vO���/��x�/ֵM�ֺ�d��m{��~��Ւ���jOi��S���#w���~��|m����{epg��{�}q���o_���Z�/yc��IMm�*Go�;����D˶m^2�۹q��]�v6�?�eY������N��Ȃ���t�~����0?#r|MKX>U�����#'>/Ͷwm�ү�7wVKӛ#�V��~���o�1�Ћ�����{6�v����g��Yů7�H���ķ~����^�y��Ȍ����nZ�S�~�y�o�����.:f����]O��t�mÙ���|��O�B�,=Q:n�e��ʬ�c�{������Nm�j섭#�O��m���}�S�~?����~W<����r�9[�ܑ������[ߡws�{���Vק���t-AU]�=�d�{'?ٹ�>����޾hЖ΁�����[&��j��ng�;κ��G��t\��]8~Y����N�n�"W��+#c^��2��[dSʄ�����۶6�������5���=�o�O�ە�g����e�����}�=�b짷N1oK6�Y�Yߵ�ew�e����띯x����s��X1e��GW����u��/�-^��'���ǖ?���?{)�ʤ�K�:�{`)=v�'�Զ������=5΁���Z����3���UT���TZ�����{�_^���ջ??�����9��lFݽV|��G�k���:O]r���m}���T�]zm�ѭ�}��������+w��Jz��۝��^���������3&W_>�}��y�O+o�uu�w��pN�qS�}��/�?�����{�YW���,� ���'>���啇r�/K�V�e�eux|��ӷ������)��,{b�t�Ż�ܟ���Ӌ��6���ŗ];hb��?�xuk�\<�e3̲�',��¨i)+6-�=�`绫j�o���?^T4q�GI;���7�W���v�+nm�Q"z7��E�$D�%B�D#ʈއ�K��7�D5D1:���s����z����9�\�}����o�m����%B�:)&+���>�$�ے�O�,z�jz���y��=S5��`%Z�yj7lN�Z�NN�y�R\�(B
�x���gO������Ծ_M���z���զ�"�����0O���&\��8��[ʌ��#v��xTQK.~�� �/�ө���#�C'�T���x�7����Hl!�V�T����������x��;�/:f���S;�	�}��o�t s	#o�Wp%��֜��J �% ��C�ʟ3wb��5�
.�=�6�D�ň��BW����:�^�t�8���
*e��z�EFk���Q�i�G�g��ؼ�c���{�vuL�a�2,�-��b�1���w';V���B��ֆ;'@d�w���}���M��9W�+w�2�7C�R�U��~�Ės�do�T��d����$L;NXj2)H�#�'��"���x+�p�F�g�*AH8z�үYo���A��!0�N�:x���\��$��ې��l�~��ư��(�Y-Dr٨���G���Ж5�@P�jW̻_�}t9\\�@6��i���k�Ӻ>|�ޟ�(�<"�2�I�� Ţ�ƌ�,lo��B>��i)��������֑Qv44(Z�H�XK��p5���lI�JE�ݜѶA�U�x�U�����#�؊�j�
+=9���q/��O�p�U�`�Iu8E���!����Aバ'�|�"��L��6w6J�Y5E��g}IB�f�=�,������NV�Xb�%$�7,8il��ai�����\$k�u��sh��-�:��h�'�Ħ}gNE�=JR�y|�q��O����RG���7�����-.��I��2r^x�/��?�:�'{g�N�R�h��Ӥ	��\gl]+CFh^�E���Y��ת釄�>��L�^\(�dE�{k��e�N�h{�n��\�l7�O(:��"��dY����������W���ھÎ���r2r�������b�������������������������������������������?�ɬ~�s`����;�L�$1�$ɞ��暮1қ��9$9�xn'Tj�b�m�_�7?�9^�~�hd��d9����>]��q�϶��3VG���7"̀��<"k������@b)i��+ڬ�'є5�"��~�G��qj��f ��"����vS`��/q�����~9T��p^��V,��U�����Ʋ'j$2/ g�vb>4lKW]�Ŭ�cZ���J�]u������ %��L�O���� 61uz��_4����-����?&=��e�˧Zb��uG�3�i����UeJl�X�yBl�I�9O(ʻɭ!��*��=ÜˊtU���8.A��`8����l�3@n���е7�=X��p�<"���g�oo״Wu�0=ƸiFZ�Y|vc�ɛgj�
�/��7}h�=���H�6?j�n�4��K���Y��	ʲ���W(D��|:,4�NG�s�nd'�Z]�3Œ�I*���R�޺�䰣Eχ��\�O��}�3�0����
�͉;�����o\�@�ӝ�F|a�1e���������t�?:)D��5�^Ѱ���-�9�b����K˂�u�5/FI~��<�ʿ=�=S�{�B����g(�p��������G�
m'l�i�7���X$�>-5�M#V�Rf��@e(�>x�֮�B���}�y	tj��v�6;����X����j�V�~���Kc���`K�,�qw�f
��O�n�b��L2����0�|qN���G��Mf#�'��M�D��gQ	��:dq���902'��jD�7L����&8��Z�a��o��P�C��/��0�����ƣ�����I�R�lQ��e�/_kI뎞?r�rK��W�o���pl�d.&0<��#Q�S����rGE1'��3=pNv�����=�f��l�����J��=�q��_:��	6c�̩�F�n�'P�<�X@�[�aT�͐���d^���6�Y��9B�९	w�c3"R��j�ij��3dӍD@ez��}��7:>���H���ߐF�	v��|R��RF鄯��ꉠu����	����Y���~ �iК{���i�r�C�Vj6�؜���W9S�K�
_�\����<�䬔&%�p��!�M�U@QޕX����D�Z��y�έ�TP��s�,� q����3�~�!�TAG3D]�ǘF�1���5�1�\}�������8��K��z��x����=�KS�GT�Uw�B�U���� �߁4���/+n�E���Sc��8��lZ���;,���2� S{St=i�~�Ԇnq�>EYfCɭS�J��)!���e��2Da@�=8���������@p�$ҚR�d�ɄL�@N�n0	��)X(���?�5��_v7�5��W2ħT����#��F%�E�~�����K�G06 3�Y��Cw3�ɶǰ�{/p���Y���i�GX4�zd��.H	�"Rxϋ4�Ҹ�P�c 3�T�� ���۷/���1j�hrN����K(�|8͝���o�����Z���|���]�F�O+b֊�g�n2��<N��.W�}d��g �䏹��]d,�,ί
���H.w'��,�����~��~Pϙ�UJ��N�}bvo����Ѐ�7�
"n����ո�j����k��]�aݝ�߇#���S=f���!����l;�٘^�á:��a�ꛑ�c��a�F\$�ќ��tΪ�s�&|����9�DS���(�Po\�k�/Md_G8�k�0X+>�Im.��W�E�F���b5�v	~��A�I���o�
�fv'��I�X�&s�OXH�.Elt��So�|QO�qXԫU���1�7'XF���Q��6��j����{��ʋ�wf�7���N� !�n+����>5�>-Q�h-�©����<c�)�,!3U��J�{�>�� �����y��	�Pɮ�Fv������S��e��/V�}��W��8�b���ĻP��|����d�YF<$���Cb�S:�S���b2���������]ݹi4(" D,�F�-#�d5v���Q
%��g�U����qS���%��g�6{}�0Y�U k(��t���YqF�@v��8�+^$e�d�QA��̫ҟD�\����uӠu��?"I�"^���[� �e�F?	j�����jz��9p�	,��M���E/Ϟ3����.=4CÓT^�4y�^���\>[?�FǇ%�>(���($E<}��5j1�B�s�O._4lw0}�m�-OX!x*�;�QX?�������ʛ�m���a/7�q����n�xSc <��4�PΞwo��:��Ϫ,Z7�f:v�w%�c���!O��:{(�_�\�4�_o÷����1�7W�8jL�Lz.,8� �:�'c[��u�3��W+⁹�2���_Uu�>;��;+�Hd��8�}��sZ�g�4��+)�,�I��*Հ�J>�}8�c���U^gu�c_��ƣ�c��*����w��HV��}�Â���<���Ԭ�{�\�v�w�z��)_-�X	O$V֕ݲ��wQٕ9��E�
_q.h�Q�����ߟ��8
첇��s�TjPC�1� n�r](o�X��G��c�ȍx��=�Ɔu��B�y�z�(����>��:k��)��E�9��T�Z��C��q�]m� �-bUo��E&}��{��W�]�K������p�߰����|��C���'�?���?���?���?���?���?���?���?���?���?������y�菷��s��&�V��Նr�a���A���VQK�D>���კ���B��$1��<�#@����04[���l�o���=m�-�? e����Cmo��0�~�]��Y��Jw��G%��V���q�^;m��;�q�H ���%�]�,�"��Z��y5�ap�������Fξ��O�E�}z1ֶ�ԕ�eeĵ���u{�e���VZ���l9��bggx`�/p��1��|j����gěR�D'���j�U�NZ����[{/��K"��)u��"��W���Iυ>�̟W���>��ݪ�R6�,
�P7�L���п}��H��/[J�|i���ș����W�!�e�<�#�tdG֖Zx�1���`���F���r��޼�=�\W�&L`���!�h���إY��v���� ศ<�Ec���<����2��1��!%B�7��l���<m��<���"O��C��mV��6�ݫ��~�����|(}�\<�^�B��z1"��{��&(�>t���5�s�a�v�c�#�˫��Z���VU��lթ�?��M:�GX0
-������t�".�pdՔ$9&���fh�P\��ݷ��p�����_�G��{���؛�o�����, ��ݭ#�>��Or�S��8.f}��8# ,/�&�t�XwJs��4Z�`��]�P��	�e	Lި4Ŵ=����M�ʕ����/�~VNCi��L�mNƯ`^��k۱����{�y�w����
�u�F�����.��e��ʱU#��_���vP%�J�uK��:��O�tӭ�����$/G�w���m������Ȓ�~��ۖ�|Q��������ٯ�ۇ�=)�:�&�OAC8(A�3�2��f"9C-$x�1���V(^N�/Qw�f�����`g�f�ۤ��'��=��Z_�T�����J�,�5�$��=3^}3����J���0\J=���8E'�o��QR\�kԼi��5$��n��ښ��ׯ�mdfCs[�����Sl�seO��g�/gT���	Ҍ��W!})�li��jO=S~���5��¢ߦJbA7w�Է2�8�_pa�_k���
��;�NQ��AH�2�������}�k�SOz{��bg�7k�6.�:�1�����kv?-:q����C��5�B��V��娹z�oJ����zpP>�t��,1{��wnP*���wʑU^��R�%��ot�޴��A��+;Eno�d�{��:��I�Z~=���Q9j���|#�8`YYIc��V���������d2��	z��b\sI=���@�mg]���d�v���#���$>��ӝ!�ڱ"��x��@��l~�v���
��-����e��?.6�A�6na��Ϣ}�m��l_��3���[��L
��ض��%����.�P�����c~�L�ꄝǃ�FH*;��?��ىL��*�Ѓ�E�{x�)����7�"at��>q뤋��&��yz��YÒg��QM/�\Zr4t�/��s#v���u���g]�K����%*9ֶP9k�ݜ�����d8#�*Z7���ܼ�z��U�G}Mʇ��ͅ��Y%Q��\�� �ˋ�x�=P��?�·�{��&GSC����8�ݛ���Z�[�lCm
���->b��b�qr,޷x
���rBO^f�C'��ݎ�=�U��*��%�)<�
_nr�
㾿�SY�v�V��O�K~��g���m�� �E�
��0�l��v9!c] �����[�Lv�NKv���@"�!
K��
�L/s����o��bz c1tA�7kĮ�xR�E6�'�D�� :��<g&��cѸ��Q�G�r�Y���ٵ�����6î���^p����JZ�����5|B5���@��s\��dS�j�iל�F�H����V�uG�9?�@�f�O\́��Za��p2���h��!�~k5ƵG��AOvV��*�S�H���5^y[���V�C��T=m�h�����u�'AE��[�y�m�                      ����f� �  