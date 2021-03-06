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
�      �;	xE��<�y�®(�+���̙̄�#!��I &�C�L:3=33�CwOn���9<XWԇ������F���/
��\"
<��_��3=�����~�I}��������?�Z��:����~�f�68+��gٴ�j�f�����tdvdt�����n(��c)�"�Du��L#+�����&E�_�����h�?��Y��������o���<�s]����?Ӟ����23uC��!�����k�Y�h1���"lie�{TI�3Wo׍*���ʵ�|��|l�A,��#r���!��P�df&#��AR��`!2���C�4����ג�L
*�O�GTMI�3+�n�EEt����6c����y@����qJ���4P^�c��	�y�g�g�#������������m�D�w�����Ѵ�?�������L�}�:��"��E�h�r�iF��4�<����|����4�nҷ�(��q��X3��6��r����岻\���;<#��C��OaS���d�Z3^�6�>��;R3�p�6�>���/�^��@�R�����N�����s�6���ǖb�/t�V�c�/(�.���g����\}�n��Y82�`L�>K���9��j/�Z[Q��e�\$$I+�"�z�S� � Ä��P�װ���
���(��\�$9ZC�a<�)���Y�X^�V�3A$�!��H�Ì@s^�hVD�
�o�Xp���W��Xʒ�r�LG3�3b\e�Jf8��$�AfZ+j8����2�y(&r�����]�r|,B:�a�����$�!F�3BW�X'����`��e����Ҵ��+��/t�˫�H�h�����H�on��Q��_V��XQ��:�#z�H�x�r@�48��O���0�:�3�t�4ܘ�3A^-�~&�m2�n#V��#A�Mj����y�5�&�H-�T��Q17�O�G��d��Ib8	M��F:�J�ܥ�z�_ /bv��P#F�HMM�۳)X����1������`h/��v���^�#E�X������h6��Fv��dR�td�f|vmZvg�;� ����3�*&<L��U(�I[����QR�����	!�q��n,�ǥ�s��
(���ҏ��
Z�ra��Ő��V��#T���8��8`��
�~�@��VMd��,eRk\�p�*0Byy�K��O+�$�HgecE�q9`���L�N�5�E��#@�� O6����|�E]kq�\T:"��P&�J)�p0M��;#��c��CF/��Ç��@D�(0uR��8�1��/��%�� Z]��j�Lʋs���?�b��^Zb,b��it�3�̄����q.������/�X4��9�kp�RlqD,��
���	��>Ĵ-��M�fF�es��!Ʀ7'���K�c�d���hr�A��<:DC���(���yA��\:�����n��١y��z�m��MȾcK�
Y��m��B� C>:(�
F[�beƨi��GS�S���H��HBu	�1��6���2ni1H��n���_�YM!��#(L�3�C�[�f��!G<C�8�]Ȑ�ʈg(#���.d(#�!Y���h%o%A�l=�@u�K��- ��#����Ö#�%#�SPǙ�f���:�*-c4���w\�ӔP��(�MkN���0��|�!J��ZT~�"�W��H+B.��Y' `t�����2[' +~���sc8�_���K~�L2��A��A�NYZ-���Vd81��?��[�Ȁ��Lk%��j�ِ�Fk�A�{t̥Зy��c�"�U�!-�@f�5!~Y0J��;�C\j=�i{I� z	!�y�g�โ�vL�d�r��jM#�mO�,�,�\��k�u�]D���_�ݑ�x��58����Yi��/)'#�w����ܴ�	�����`jI��A��&LK��>YЀ؁��8��]��/�_U�O"p�)�_f2�;�b�xH���$�M����I`�������R(lU�3)��^�,�	F`1�D�d�,���>�O�Z֏�tP���aΈh��I�ɧ���_��ҁ��sIw��6G�Wҁ�!���bB"#��tdKGxȔ�SN�1����2n���ڨY]+Z."�f�5�(��ɏ�O�ߏ���1�?�
O&����Z��TFe�
BAHN�OR�?�.�1������%٩仇e�
���Qe:�B�c%e��3B�O�;7�ǌ���Fp	`Ս�wşo)��|�{�Kȁ]X��QJ�"2!,�H��$^�P�����#"��.���D�Zf����Pn���
�m
EX��f�y��x��Ubr0�����N���+�
��?-�%Ŏ��"U
����V�΁l�h���ƻHu��Uc��r)J��A�,��8|@UX���ȃ4#��UG����bweyuE�L`
��	O��7x��ɯ� ^.AR����ذ��*v���T��M����SQ|�U�U�/�(�Hy����`K@�É�l����`�
�9�C[�v�Re�\v'C���7Z�LF���imfíF�l.�i����Z��hml6�Lz�ˎ�t|@<�J��u��\U�/�^����a���YQĄ�xuf�D$!��B� ,��Q5->�B� �L�a���t�ex{��� �D8�+�9�����;l�SѠ�_�o�hT���Z��'I\��'߇�y�����(�`XD,�v'�^��9�ɯ�Y/�&o��BB��H8��|Hv0��`f����H�����G4�> ^
����8/ㅊ _����뜹R�fA���`6����T�J��r9�3���`�C�O�47�ѝ�9D4���BU�j.��k,1RL��F^@>�D�AJ�q
^<ad4#LHULSV>�rW�����[<��
xA`�,�����E��� ����G������h��#� �h�i��"(�bs@@�s:�dzc�tƚ�O�x��zUͣ�{�/�d����I�"�9�`֊!�@w\7p�]y����4;b��7ka]hn��2T �D\)��l��%���H�A�=��`�IPǧ�~�'f�w�7�3��댩�&[AW:��5����E4�b�b����_Bc�?Ϳ�x�����\,�@�t�:O���7�/�@.	!���!�#���9Ҥ�9��/f�s`>���8�`oA|b����D0���(�x�7�4@�$T`����o��S4�#
B�E�wRP��z�����jxSp���2a�xvx���RS�|�޻���.����.�����a�e1@<-�؎�����*��I�v{�� �N��M����>^AF����l�<o��5���X��6�턜���xm<�3��|Q��BƆ:�����(�Z�^k�G/�Q*��: )��M�?%WJ������R�� ��%� �`s��*ge�HgYA1l^�g��m �JV�~�|�`B�w�aٟ�D0J0��w�L8ȃ8�^V�h>�X��"�*h	i�PA}9�!�Մt��}_����M��K��9N���'[[5p\� �.ʏ�h�^�"G� �r���~�)�~��Jq_��bű\�i�Xj�o�T�$YB���W���Cy�yj���zI�N��Jɕ	�v��$PV'a�����ћ�!1K��(�I5�,-Auf\_��Q+�cd�T�l�[��RE$�:Y�j�$˪�5"S;��'{���w2
9�S��z�e�/S�ٌ��yh�@��sqI��+F�j�Q.��w���㰔��O!��4�N�A��A���u�g��1��3l���Z��ǩ΢9w{����u�5J٪_�2���J]4j������X��������5e?:�N���7c.�}N��W4D���ԋGw�y����/�X����MhŠ�/fФ]��w?��~���CW(}�������7�#������ޜ[���57mo/�����k����^�.��_9�O�ln޸���G=�o˼5�����l�a���k�|�w��l�χmY#�j��l����[W�|��{Ϟ�|���%W�t������u_���ir��}�����p�^=�频Oh�H5���|�;s۳i����k�ƗF���i����x���W}�=��$÷K2�#�𓟧��tè���P��\?t{���黎\�_Wd_b:��M[_����m�����y�����|�͹��g^h9�~��/�g�n�y���ܱ���Ò9��_��'�ut��!��^ٗ��?t˷U��������;u��rӑ��5�<�ޕ���f����o��s�Fηt���¾}�ϧ;�Տ�~ҷz�Oޓ�����u��S���.{���/�d0Mj�O�x�&��Y����ܵ�n���o�-|{�ܪcSW�����-_�>��߻~����[���a��G����\��Vq�g��.^w�f�G�f������|3op�^7]�����0�ȶ�z��X*�я9|��u�n��;���p���=������7������a����gK�TCቒ��̫?ް�9��P�x@�㐡v��ɽ]h~����������9�?���f��^��)�����'�|�-ᅾ���5�Ч�yk{/�ٸt_���~/|�w����7eY�j��s�}=��~��^6ob�����ji��������F-{�:����4����x�����fD>��������{�/��D��{����7쒆���X����'I�}����l	����#����6�_���u������F��_0�kd����N[_1���E�_���w6����p�#��?��b��w��m��/����~ˑ��׮]{��ϣ2?�v݆��w-��f���E�����̆����J��g��B}�~ӫw��*��=#����e��sKM��w릭���`������]�U��/fnڕ���7����1K&�v��舝[��n�;�z��i%�=[gq���m}����c��-m�5�'6f~��V]��/yw��i?l��;�҉��}��ۺۯ�n�����{俵q�}kJ��fe�pL�:��rO��5���4f�[L���[;{����o�}��!ᗟ(�gV��Y'��>�Гf�z��gM|U�΂��?�x��o�P]�{z�"罽bC_����K�����5s��-�捛C��=EEW�������7�����ᅛEj��fΨY8}��{����C�(��'��uڶm۶�Ӷ��}ڶm۶m�6�y�o�j�bq띪���T��J�H���q�]���m�zu��w�ѵ��m�����^߹��W�u�?u���D��h�|���?��|�Uו0�Q	�1c�ʾ&v���	uh7X ����xu����f C�u��Y�\������^��oU�/�oO���	̱�d:;�`�@��p���@��W��2X3Au)�� ��rB��T�� z:�����W�|{ z�	>C+��9����D v9.��.�E�߷�k��M9E����+�N1S�_.�gq����=zORԞz��e?�/�MZc=C�yb?�z�����0"��*�F�(I"L�A�e�0J���\&L��߃����;���h�*{�������o�{���\w��O6�-�*UJ���f��X\⁖*�*}#k%)cԚ�Ҙ|5�VK��|�loȐp���Ƶ_"�� pR���J�mx=�d(�ߛZ�
�_����rE��G�/�h�v).����\iB5|<}��N��@t�p8eL��2�h�����#�3�����}Fi�����SK���v$wb6h��ÐvW�}���D��ȇX��]��	�c#��k���O�	Xs������P����_��qy¬-�.d����)�Z�]�-e����[`���J�����x���h�$Gt6�������p�j�ZH째����J̷�+S���y���Փ\e@}gx������%a-6��]*�k-Ui����^z�� ��-���4� %���BA*�ҕ���h&�$��M:$?.]*>b���H8�t!t������� h	j�047#DCj��$"3�>X{i%Y��v�����_����W����.���P%Xڈ�	x�}.*�rނ����=
��6����p�hDG�&+nP���/Ӝ����I'yѼ:��yxr��F\˸�0c�Y�j�I$�e{P'Ö%f�1} ��gXH�7z�Ua���?� >�,u�퓅6i�ӲAҵ�{�o��x�L��A	fy�ŋ���n���v��H��Mx�F��T'0������J7VQ�*eQ�ޗ��@;X���o�J�J#�����íMƇ��G�D�+="�e�JRY��n�2�
ܲdN�:�����l2݂�;�N�X�.s`ѮB^��Zb��=:��=�A>�~d	y���l 'NJi�sטi���X��8�r��&�xb�;oL�C�}�>����B��B¸��b��ڊ���E�J�zr���N[���lS�K%�ܵE��k�n��a�?��0h���� �V���A���c
9'F�S����F�v��G)<��/���AL9<�5^)��[wJ��x$Ln�;�M�i��iEM�0"�6��?;?����T� �T�F�ȫ�r���Ua��A��7�l%egC's� Wܖ�@b�ϊa����Q�Ve{I����:��Gr�$�iI���u��wϬ��䔉1Wb)d��MS�+�U�R'��S	���j�8�V+6�)�Od��LT�%�u�H"-��?��}����R�ǜ��#�����/p���M���-v�|�f}�մ(���v�ݩs��z�����JΦ����ua岅k���D��^n���#��3�����ٖ�׫��JJ�@q�:��\�ڝ1��SV�BnQ��!l�+�}�#��JO�>�ײD�b)��� <Vn�@��ƶ�/h�>1^A��M��K*<8�0���􎝻yD.̛
��|6��|��������,���I4�˄*��>Kڭ)r���t�u`���r���g�>2m��]e��������W������!�93jr2����o��.(�����|OM��r�����3n�A1oc�M�
 }��UX<�tX�
^c���S�'��h�@�*^�h�}�z�?�뻦\������*4I����I<�s�N!�!c`[��>%���Q��3�Mo��G���{��H�é�� ����Fc=	KG�M�<W� @7��7�w� ��"Z1E�^�چ�jTJ��)�1r��U��Ȏ�'����h0��˕�%���"�*����  C��s{��,��|�5F��~�-.�҉��,���Ǚy\D�r�j��TZ�p!�m�8��`ч�Q���s΍��M��|9כ�����	l�l�l���4\�C�[M��:�6R)�������hI�AT-Ù�3@��ю�z^a�J)����O����a���j�[5W�7���/�xf��!V��Q�HmC�o)ki���L�~K1��S��`�m��1����������u��`���sgt�vt��x�$�|�vK��~Q��I��,��
�`�C:b�� ��\U��2��9� �?5�F�0�׬+:LL4�o�)d�q���khǲ�}!�1�Fo��kڥ�[n����Ӊw6��\�)����h�)�{�*�V0��iJI�����N��H�#8Ҋ�OFo�t�tr@y��kc�<���v�r�0
������;�����O'c�9��y<�{�����  ²��B�G���K�ZK���N/U2c�/�!8�y�LN�t���	����24��#�M��Ys8������L��E�f�FT�����H���ڶ����iGĺ+��
��m5[�o�jB��<��Ev��u�eS��ΆIE0)��W'��[O�b:d���p��zޅ�߶�߇�_�O�QV�!.D_���C�v`�ڪ���F��%Zd����o����?ޮ��;\�T��7�m��֟�v��:Z}C�|�߸V�3�?�g���G�8�jqfvc�W��X$'�$ ���>vc��ˡ}�0�6ޒ�=Ҁ�S��Q�K{Q{��������Ŏ/�r�a��BO��B/Hl��� q�@���k�C�μ�kItw�(S^�-��nO�����wcS��?�{z"���w���Ѷ���B�w�������JGebS#庬ݕ��K���#�`W�k�:ܲ�����O�wQ���#E���UGs�E�g3���h�SÓ�k���/��ۢ���<[Δw��̟��ߖ��g��Ώ[��"s���N�8l͎��\�2�%Y����1&L��EaT��r�5v�6{��q�: �
lR*m�B�������g�Ң��ŊI~��ۉ[i�b���M8�eqFY��إ�zZ�%��e$��ک��A�HkSR� H�� �L�`�l!�; ��0E��fIz0�)��ӯx$xz���P4������)x�5���C�D���G��ڍbB��,�6(��e�'H�;����3�k�
%S�����ny��"$sZJL-ҋ�
*\2|�;'T�F�JdB
@�Dކ��i]�jyӳϋ����9>^��[&P��cvzy��{Qs�ŗ���$�{���n᣺˃�=���9Z=���1��ʵ�ܠ�\�յ�ԆL:_��S�����e���������
��*Ȩ+O+�e�h5�Y�+gS��<.�_M��3�,�I�*Ls���p&�o#?)D˹?�o���m������d�o�+���r��6��F�^�v>a"}��cI��X��4� �A1r�+*hz!6c�=2��^�;�p�dO�S]!�4�X����K��$��o�s&؛�(�^��ˆ�z,:���U^�Zu�M{��=��UD_[���0����T�9%��
�ҵ��t�v�e�j0ɡX:;kID���ٽd�D�������?Ī�J�<��`WM|��r�ۭ�m���|k���ߧ�n3��5+�
�C�v�"�<���pm�JTa$��Ǆ80���	��C�_d�}�]�'��l��З����w�؆T�i�v����YJ���tt:�_���M�D����nQ^N��v�!���u˕w����68z!�+�*��&Ǳ�0~�R����eb�zM6�t�/�QF�ǁ�x���� �9-Ag�'�A=�'�X�_�%��f܌�xkX9�m�a���m������*߾Y��)��P�퍏EY�*�Uؖ�?�/ٳچ��\v4��1֭�+�P6<���Ƶª�66d�}��Ūm�H�(i���Ze����~��RϪ/��������m�N3@���:��}&Nw�C�E�x�&���a�LF!�h���|�Dn��C٦����	�غ�T�C�Ǭ-"��]@�CA��OTӾ���{ZH�������1��+4����?{��H1\���*�9;?�N����� E6
�pI}GI�f��[�ʡ�����j����U��Jf�¶�_�5O����2r ���D�i��ěm�Zd����5�8U!Xƙ�����G�o��}����T�i ��y���B�t�5�ԧʶPXϼ������,��-�ys�M
,7Ԋ�.u� Ovq�e�Ƣd���E-��9	J�ϐu5������R;��6��"i�w�y}>��ى�~v�RdsZoU8ӧ��e���+�,<���d)t��!2G 
����g��=�2^�
�ܕ�ւ�ဇD!J��'�usF��� \�"��F[��U&�L�Ym_7�;b֪����¶�����ZY��נ^g�ex��c7�t])�cM����Z�1�Qko偞��dr-���ū�p�(;!��}�|�|��5gy�C$5/F�*�ɶ�g˫W3}m�N�lh������@f�O%�u�՘}g�P5�7#7w�K�%���k�t� E��h����\T����d�S\Ƃ
ey���!71ف���ߐ�Vz����x�Y��+0> �������%'&"^�h~��@-�ٍF��S�U���rG�1��KE�����a���ˆ�uRz_��^l�P6[})W�{��S���Y�Ehy��݄Ó2�:1h��t���(]`u����N_����"`�ZHzF��:��n��sb�b�T��}%����v��>�D��֩�V�/�*�� cxͲ
E���5�1�<\7��ah�i���m<�k��r�����2ÝR?3~"����!���fv����j����B�h��g�K�R1([1�Y�j����"��?����Pg/���d&|��w�:�s8X�a��jAN�A��HU~�����Y�7k<�ۊ�5O3
����`+� Ѣ˥VA%���qvu\�)Egw�΅�A��&��-�!���Qf�j��I�"�l�G���^���ʛWJ巡
U��as<��rM�������	�=>1.�G�+`K���&�Ư���e��yS� L�Ѝ����s��T!$b�h���Oq*���%U@����J�}B܍^%Ӈ�����ab{�����������x�S�IT"jC��EI7V�co�
_�5P�Ѕ	Q�&�[~�/�������6��1��Y˚�`FyE��Sݻ�l�L�$+��(�1�0ކ(�٭U�D�>����i��R�f7*�KT�$�r�����I8KfR���~��P���mF/�T�l9�F�l�q�P�ao�џ�-G=I�<�귉�3��S�eO�����̢[�F~߱M�Md�e�X'�;ô���u��nSd���ޅ~(�Ɋ��g��M&eߩ��.�o>�E��`��ͱ'��K�#�A�^+1�G��_�:�Έ�UV5*�kJ���V��s���叀q�5A�����w���@��˥f�$��*v��{[��9dR�fT���8�P|�'��mJY(X�~{'���੭6-$9H�۬���6s4B_��4 ��c"k��r����;����Аz�*�H����-��xw90���sZ?��q�ܝ���S-$m�i�S"����������������G���n���E��,V/��;ޤ%zZ����V��;�}�8��$����n�2��٢��[�d�9U���>�D��Lɓ�p0��گ���U7K��ّb����#1?��� PB�Ee�[z�Q��m�Or�rŤ�Ф�2o%I��sL	0g���]r��b�7q3;[��Aͭ�Q�A_s�mo�Asl�SuTA�⚣��g���|���%a��;���{����V
~��:=Vȍ�����V+�	���p�͋⑓ܤpD3�Ucn�^:�h^�4���2�l�ܛ��P��0��F�����!�N��x��̐��� ��זu��+�/�ƚr�\�,'|�(/_LπSK$�ZG.�TNʾA�(��w`�sP�P�`:�Ԅ��Z	���A�-?�?LQ����?���������x8jXP)X��;�<��
Tc�S"���r�se���w^3!�+t������wlIN�D*2f�N�|髉6��'���"ˤS�6�6���~����$Ko^��t5��3���?��i]:�M�.j Z�oAh$�Sq���iA���9��l	�:а狐��v�k��������|�?Do�"Éc��Ӱ3,I�++���<U_�]��cM3Ɠ;���"Ak��I��M����S����W�YS����"��l)��4pq�T��S�K���F�v��Y���^����ਯ@���;��j��/{Xb�!�\�1[�_F�q�:�+��� o'���0�r$�1'dnJ�0'�l���򨉘�bk%�B�EITl��u���v��xrNV݉2�5=K��t_���z<�J��,��h?8���H�ru�~�lO�W���SYOw��0�auNRE�����a;����+�V��zзU���X֭�(En���C	�Ӿȡ�t#����i�S�4���S�e��+C!�%i�F���D[�ܢ�'^/1��;p�����{�T6dѯ�+f�y������J�+�y�r�S�s��.K.]��P���*�Cɕc��E�/h>bc�SZ�u/�6�E7�ʇ�y��,�V1Ū��zU�����iS=��,�4L7�J)=�~-��*��	�-Cx�qy�:�I��[���}�3p�*���/p̍ƨ28�55z�I�$�lf0%�(`�x���G��L��=\(����ZjC��)7�[�?ٿ0�g;��,|F��]� :����>��5%�3�W�S R������h�}��n�{�+��4�
��M�GZ![Iqd��f�_��+��1k��4�d�)�\u����>��LwX��%��NiS^�(�h��U��0�hp�9�),���_�5[4~jE�V�oX$�Y�+*,w���Y7uDv*^w�z��<�lR���$��xN;8�)w�2�otX�W?)�J51^�&�����>D
VR�U�k�|jO3��.�����}w��z�q�_�jhm��w�{�|�{s/��=	��x�{�{G�
ʭ��MY̵�O��}m/z�N cg��(�8�;��-�I�=�/&'n�!�-2�i>���H��)'�������M�^�+_3����.؛����ߕ�DJ)���H�xe�o
!��U��dlź/�4Le i\\g
y���PLN�Sk�����]���^y��ll��p��ϓz���BMPP1�R��ޖ8u��tQ/b`圲�V�6*����.����������ü���q��ŧ����|��;���r�B���(I��]j$����`!��y_:����`A��5��0�	�EC�5��@nR���p땡��709l(Wg {B�~|�J�]���k�;�� I��P�~��쟿k,&݆Np�b�I=��}�2�-�J��O�[����#Se=�c�a�68�n�����Y�6��g����8b�km�΋�`��fpD����U�lf�g>��l~�����{��(�3&�°�G dڜ�|�����Y����U�_6���?ml��9]�D��ܬ_�9� �T Q����pwѣ���g@��ؠ͈�ho,�-Y�^�D�\ch�B<�)�G5��~S=�+�u�֯���T�LO�<�x�����m��f7ɷl>��-�ל����������n��lލoW�i5�rS����d�Tݐ�+c�1��;����'��7^,�
|l;�ѭ?h��ǁ�T�z��rp���$M�q�_V,cCF�a�QB�oxp8ZE�p��`$�Q��ف>㲥s�=�gVq=�'N��Л{:�V�-}�B�o�H5��"{�-� F'-�>{�r��e���U�~\O�!֣��M�F �zbs{�ܑ�F�ɘ�����.h�蛰�K�/��蠨�~��N�|2d���ᶰ��y6�ܘ(� ��oEL�}k��Wޖ�>�W޺�#Y�686�1hhB���N�^I^����.^1�����1l�x��Q�B�c�k�nR_5x�&���3�DO��z�Q$�^���|��]~O/eu���s:�L|�'oŷ^����O��m9��kz{1�cG�C�����;�\O��=ޮ
����B�X��p�O�����+�(��oq�\���9�
N.�?Ay���VW?M�7�n!8fl�.��3���L|��Hy'��R�
&$|�0�>rǹ}��)vgB4vF�>o�o�K����o҂R�V���@�c:�zD�b��\!��ى�|�[]#�>J����p�_`䀥����v���^��}Yǁ|4�~R�k���I��ɕ�>9\#*�Y'*��˹	d#�?u�t �#o8x?�\:q�j눸���*����ȩ��u�8w�"�v��ՙs#��ot��~��a#ߗӓ�5|��ʑ���n�����60ՠRMV&��f\��øMɃQ-&uP����F��6��Oq�ְ����9 �p�O�W��/���#{:s��bC�T�G�Ȯ���,�w�#t�ԍ� ����TftA�y��3��g乯���ȫ��d�	єN�o�zP��^��}7$0F�"s���a ���[z��Au����Z
V�������|�r(>�ݞ���r�p� .T��2��������F�����0�*�1���IM��B�g'a�bM��lgl�;�nn����,��<sy�2����i�}9��f�
WM\z��F��:ro��aI�J����]��{t�(�ف�	���^�r���5r����}��A����G��n�uHUR�cO��E�����Dg!q�,�I�Ξ(n;�� � џZ��/Ten��D�f��}:�2���r�`'��AH�)cB�1?C��J�wN��f$ B(��])[����!� ��Z�����������s%�br���P�^�'ހ��^4��yٽa��8�ڎl;6�@�����N��^��̕�� 'Slf r�;�{T�9��q���ޭ�N�Z�)m�rc�u� ��(d�C��X~H�T>��5pG�t7�o�1���'`m�/҇���5���j~RA���Y?~tq�9Cvi���y:�8�_�=�~ˌ�lC��hr�=�vJ!�%@ #���:�H��g��m�����oL֖�z\��;���1�X��]Ā�=�����
;@\�O��hP�~���_xl~z��n� 7\�x�G�^�X���BK�8��fд��CP�z�C�p[�`F��}����R��.~�	�S�� e z��^�XD7V�EP#d�af���� R��;��a������e�iIz�����z^���f_��~ɪO-B��v�t�41]�?ʰ���J\g,�T�>w�!��Y�]vmq��vhP.��P�&jt��Ul�!�K�-B9Ǟh���}cb�P�-���gS@��OQ�/�; ��{��9,���}�ى��|v�ܽ{�}�h̤^���yb>����y�}�x�|�G�_$��Y�3%2mgd��,�߀�������h�z�3��&��4�n���}c6���*$�{��0��D��48)B	@0kG�du�ߪ8AJx��@M{���?��t�N]GZ�3���h$6h��i�!<����݉�_}G^�5cJu�}hO�	?���@y)(����?���'�h�u �\E�T��_2�Uo���n��\�wW:oڇoVU7��7���ƴ������,{w#�jo�K�u������N�8�7�{�l��_%�|��6�7�qj�@$`�<O{���Β�:Nd�'k���r��K�s}PI��@�$�E��ǌ)�Ή8�gJc��0�Щ�xF��)�|B\&&���3%�� ��!���J�F��r���"	�k�Σ#������t�~]�ľ�Áf0��\�EQ�s�^F_Ȃ���)];u�o�=�m�����Oi�]^���x����$�rZ�?W7Q���2����𱊶;�%�.���(,���KA��)D�{���9��覦�x}�=5c��4g�X���

�?Z{�D�H���Z�|Gȁ��K��.�������E�:���A�|#�S����Z��F��Q>mK>-+ci?˕B|"����^�M�%Pf
n+G��1�|m��n�������1���!k�Ln�������������=����1���/���_~�������_~�������_~�������_~�������_~�������_~�������_~�������_~�������_~�������_~�������_~�����p�%�[/��@�~�bYի-�(ۘ���C2����5����计�t�x���kř�"fgX�N)sɤ��_4��	x��I2�������U=f�~�.ژ��%������+~��-�\D��t3���%e?	�Y�Ym�h�2P&��j��ٜÓ�::n�]ڀ��2 �wY�z��n/�![ܹ��5/Vi%Z�l��j��]�Mö@�f�b$p��p�Ϙ����E�#?��u|5BY#Ȅ��g�?�K|�gA��M������m��	�u�$'.tD+�3-�s���=�hn�9&�?�pi�/HR�Ra9v�DRE��j�`Y��^�g�y'Pg�fl^�UxZhm��@�a�fC��s+g�P�G4m�UJ\ç�i�ض����T��6��p��/Z| <��˔A���-���
���Im�K��THLՔ�(j�'�����ϩ8�;`��*��Z*����y�nR�H�N���y�Y
�a8�O�?un��2{���h���[U��l-��$�+-�����Q�	��k�,��BJx��u��w:�+ꕽ�m�9･���t]O��	3M�z_�NQj7J�C�����P�#;KD�q{:Y��x�^�Qx
k��3�#*w�AHz��3������;��/�,�Xm2��ފ^�/�mĂ>��:/79-В2E������`Sb��#aS��s�$~�
%�Y�b�&R��7;Xev!�[�X��S��}X�O_ l��k�d�?;S,O�{H�/f��X	�^\1�4qv�ry
�DL�C�+�<A�Gѵ]*�)$0�W�������@������߭OF:�	-J��Qx��=�(�+�2CӋ���=�o����/.�i��L�>���s��X�җ����W���0������V��|�H�!�v�0ޥ��Ө�4b���l��c�\l�L�`m�d޵��`��:�=�-�ڢ����������6�&���jI��Wk�Omu���q./��.S�SvR�S��}jf�<	3H5,�=��k�QW� �x5��L|L̼<oz�&�u:�ͱ���bs#V��,3.)R\���lE6��=Ti�5�D\=�Ӭ/B�H����t�fᏏ�bW#l<rqЍ`�us��76�EYu���/�>�����`��=�rtn�#S��+{��2�S�}C)OҜ�ء��_Z�#��Kk�X��C@+��4V��� 	[���B3e2/�f�}J�-5ȥj�*Q#�J!�ږ��T��2 ����ͱ���j_�aՍ�E�>~w����`���('G�{�|��k�aiV����}z���rFu�qǧMͫq�=�Vz�Ί�S�y�%��?�V�'Sk&�7�D$����#�ր�{o�22��4C܀HQl�(���[� H$�ͱjF>W�9-�۟�5CP��΁����z�x�9�+��J�HȓL��C���gF��`���"��T� 	:C7�`�����ḑV'8~?ު�g�(����]kKQ|"����$OJ�]h��"��E>�F�s5�d$.t�)%t���$��Fj�V�GE������|�X�B�x��CQm��O����2�S�v�Ԇ�^��-?Ў��j���gԎ�4����|/��!��-p�}��0������؉�A T�!}��E����G�v<Q��ƲŶO"�i�s�'/T0�-�r�OxN�J����bͱ8�\^}إڒ̷&����w;����g�#��ߔ��A��,���q �M+j�s=|q�͐�`9ͤ&�F]��a[�vM
˥��yg��X�V?轭��u�5OIZRM.�Q���PE	��+��6}]t�`�(�7���aO�r�I���%y��4�����Hf�`х�."�:k<���RU%1ˮy��>���6�Yl׽y�g)d�2���x������7Y��5���Xq۠���w��p�����}�e��!h�6����Ww���|��}:{�Vv3��7��m�5�AP�>�B�z��@�X3�%S��|��%����4.��'�����x%L��kp�v�'vW>��k��.m�{��U�1�p=��l���jG��1ʩV[��4ڪ�u]���I����64�Q�s!�Zow/����=���ZʜX�-�sa�M֙����GKAd�N��Xe�ߧ� 9� ~�&��Ye�}J��3Э�gkFh/&,��\QAd�!���˞�{���C�pٴ`�&�1�W!|ei�Ӽ�A���`�����tV������.@����Pu�4���]�t<����ǥ�)�ޅq,k���u9� C�8k(���ͥ�0o�H,C���;}�e��F��<'^g�7.hڲ��CHވs_gt@�͡T�̂�3��u
W#U�I�б֦�Dr���_�����d�m��}l�?�K΋V�Y���bXm��u�(��
��n@g�zV�J�-�P��}��sm����=~����{��;˺���'I����n�j����2k�,S؎�P��li���z2f��x� 32�ʫ�V�	U��1g�t��w3˷g�л�C���7��������i������=��׋�+,�($���W���nK�'d;ߩ�i!I�*���į��ݙK�����+�Z˥����Zq5�ݲ�Yzi9������L��2�cG:TS7 (�@~�,B&㻿����6�sؑ�WI
6d�J�cs����&����%r
��X��4^&j�W,��S+`*�7@;Q�6^��Ҩ��T�D�O4ԓ��X��f
�Z(Ƒ��6���7x{���J�_ۓ�����|^7��_|ؑ����n�տ{�8�����~�)T�BSY�&/�4��"):��'.v3��(ʷ]r[�S	���͈TC�N7�A5݋��k9#�k��"�٧���'�*n?.�d�5���[JW"y 5�G_���6.�fc۫V���2���h���~�t������d�k�WA���F�[&6�z^�mG3�[�;�][�ZN�n��R �{����&�1���'��ҟ�>�s@�T�ʙ�Y�J��S=ekݫ�С�V�3:N��$a>�9{�)�4�䍋�X�1"�Wooս��A�M���n�c�p�aXmih�-uDlH�y��#�n7[�<莌�K1��D���Sȫ�R#�8C*>߽�Y|�W6�M-���(�	���DV�",l<4wf��0*�滟��v(N|���=}%���񒶾y��d�׽_����MݻԱ�<zoB�4;���pi����W��W���u�\Շ��v����߻�O��u;|X~'A���7��:Vo~�D|�z���l����p!ɝ�8�{�H�T,��ұ�J�ǳm.�v���*Q{�3L���_,҇^ �m&c���ys4�L�1��h^����R�4(�/~Nw`N�,�~��gS`U��k���Q�|t�s���H���VF��0v�I/�egEo�2R[�X��OS,�M��Ggżb�.��E�2ߖ f��+z�|1TS��VJ��xK�v�-PV�U$7��д����7���������O��~7��o:��~Lu�7���빨���/R�IPŒ�_p_�h��Ƭ+_Ǜ˯[��1��:�$�ڄ�Z,�6�P�m�z_):ه�v�[�v�@��^�;PZ���G9�f���Y��?�r���$����/A�d� {}5!�����b8P8�m�4��0��F ���<�%D��-��?/��2�A7	�wm��͠�J�g\�Y$̘&���_|t g�{�:0��\��Q?��p��p?� �Cl�n8��I���]�|�d�|p�}(�j�j���C>B�<������B���x���|�j���H�%H��f'�1Ҧ̅�F��/ ���b���Љ"ú��Y5����^?Q��V�c<�[�p��<,3<��E@"H�/��ω{[�C>����Z���Ɂ'޸�/���rR?���O�S|�o*F��l��_{{������6�s- �*�X\�d��9) ��tF�JPd�rK�t������3Q��i%����� ������J����8�kBl��-%N	y؝Tl�1�`���W��9�J����_t�g6���m��7��.��ц�]~O�'�l���8��A&��m���3�ʒ^M$���|`2/�E��3� e:�_n�4��7��qyι\�2&<�K{��o¦��B��u�}Z=��a��]$&�]���+$2݅����\a�R�w�/%�Wt�	.��L�昄]ƿe�@3�}=tF`���<��4rm�|%	�FB�@�~b�JUTvM���ױ��~~SF����-f}�T8})^���%����؛�)t������c��n�]��̎�y=Z���5���N��N��y4�D.7����<�t��=��%�>S��]��X����	�yJ*�Y�!_*����k�;v�Օ7�U`+�h���#��b!�����4�{�#��3����D�s֥P ��Z�!�~5:9apCÜ������0�p�S|3{Dm!����ث����㹁O�D�yc�jȪ��5\E��ҧ_"�=+����V�����#,���f�푮zB���-CuP�t2&)t�����D-gx�@� V��;����^Ϭ�Q��[3q��l�&�HTA�>ҩ_O�R��T���CG�!��I鯺h��Q&.��?�F]z�瞚�7�U�Gc�y|�­(�z�e#)�4���#�C�-�*F�7�"��z��J�����/Z�����ax#FDR��&\e�0��tD8�{������/"�d����螌H|�;Wė�\!_-JP��,�&�-�'�GyEa�
t$жT�$'C6���x6����l��������I��&g��;k����)�����2�����}X�)	V��{#w���קa���~�>$�N,F��e��:�n�����5�/�<��Iۇ�k:!Ѧ3��a�l��w{rژ^�;��B�19�����+x��9f|!i�Ōkmb�7���-�u	��a�J%�4��7Lek�{�!Z���b�v�s���!���{s��u<9~t��!�rl^��8DJ�p@�1�[�O����?��_��&��!��_�|�iӒ0��(�F:Y�`� h᳄O��W����~!�܀��XR�h�e�"..�V�s&��hN���Y����Z�F����	��V���9�r�8fJ���� �b/�n�F�������:�: M�T�H�3dۂ�F��	����YH�+B�:ݗ��j���{/��xG�P��%}�݆ňA�5���R�����o��v��Q�8�h�T��ƪ(����Aؤߚ�U��#��6���;��<BS[C�O6�~����xh�wD�8���y�^����+�5��k�+P�k�)�n�!�I�HQ������1��F�nc
qǅ��S�CX$��	w��:���3%�(U�b���6��a$&���u\�����W�#��=�_>z.��x9��~8�eA��&!�u(J�oj����d��Yv0���'�9��?	.�ҿm��|٬V|�|8��}�Z�4�����4�[;.Q�#S�k���qT�4T��m��X1ث���:�R��jO3�\]��S���2��O9Y?.���q�#���T�C)S�W�s�]�!�҂N)�+0o�^:-�M� QUL���~��suЄ�ޤ^�-:���+�g�_u��d�&-�1�2��)�����h܊Χ���˯ !�O�w�Hm)T'ՠ��/���a��m���������]�v��C����k�U_�655��tg��`�a48Ϩ��(��Wy@a��]z�y��6��Pʅh���i��h�뻑��%ژ���A[ ���u��� ��U�|�g$Qf�ت|��;AQjC�T����%cT�?��� �S�SN����Wx6^u�f�w�ADL>U
�(3z�����"a">��6�!�a>1@���ʐ�\�ޫA�et�y�5��b��}�L4���%B~fJ1w�� �J�����4c(��]��b�$�W dw�{A �Y�IRx��#�<S�3���Q���@wd&��q�da�1��ZC�U7J�#�,R�(���>��;U2t-E+<6�m�bO��30J,�;�HH�E�|��n������͢�e}�;�^�(�i���#,�Y�4@���%��P��¬=���cQ��+:���J�ya���gQS�9��$��^���՚6�	�;���<��lz���F��cNL�����u��f	����#��@�?���ﯼg��;����l7^�l�jox�2KpN�[��{(W��f�^�T���ʉ����J�9�A����P��1*���>�j\>W0Y��R�i�
ԩ�Ua1f�≅��#�O ��s"
G�c���Ϭ�j�g<妏Y����o��_|� ��{Q�������b�o��YX��������ȏ���?��O?�ӏ���?��O?�ӏ���?��O?�ӏ���?��O?�ӏ���?��O?�ӏ���?��O?�ӏ���?��O?�ӏ���?��O?�ӏ���?��O?�ӏ���?��O?�ӏ���?��O�G�O�6�u�Y�fu��&�qF� 2C���n�14��d�.�a�C���e].�_�k���t�T�\���G�L��. zZ#F���T���
p.��匝��u���r^t���f�B\���"�k&b�a��t����̩	�#?�t�d����L
O��s�^��T%p�A 1���n�K���e)�-���wL�Կ��i���ޥ�CJ��㻮��5�R{�.�r��c�O0j!��[*y�.N�Qev����1J��P��Bn�36�2��'������^�w~*r[J�,��%Pf��ml�:�$z(�H�:'Vȹ�����+���G���33
����#���|��Ayy�~��tO�w�x��G����ʔ67�
Zz��1���;�"z�u���ڗ��@g����5Q�\ 7�6Yc��Nl�Ġq��M�Af�d�R*ck��X���!��0w����ݺ�V�F�<kY�]K�ܳ$�l�H��v5Y9��@��.@�X�`/�"�w�5���iC,�r�ôʄ����aBy�6dg\��Q�>t�ң�=����u��H�2�
�' �����z#�*�r��`��Λ8wTۮ�����6�8k7_�O�a�#����(���B;X/6h���6UN�$����L*�X����A{���~�pBh�|uΪſ T�	���J�h� �Z��Y�l[����!X"�d�\�b��
%s�rk��O��V(��?�YY�B1��ڀ���?��)@��!j���XVK�	\k��3����[��t^��[/f�vAAMP�WeV6t>���ed���re��G�`�pw� ���,M��Rm*/�V�mV���%��{V|�	����x�{�,}Dx#��k5���#�_����ӊ~��}�F�y��J�D�8����9pjy/j��<�Lp�\>�U�x%����tu�nO3��"��X�c=ONe	r�C%�m
M�����[��=���1V�!M�9o���mCq\�<�v����Ya�zȭx?-���S��a@A��9��H�%��^+F�L�_��&O+�LTw'ׅù:�3I#A���X�csT�: �qp��pݞ$�.�lHzj��[�~�A�% ��u���u�ူ����i�1�a3�w���Y���ei�c0����E�7����e.kP��j �����z�K2���^9����6(������,ʴ_RR,3�h� ;�j'��&����ki����zz�m�3���)���z���?�����4T�DB�7$�o2�T�嗬l;z�~D9O�)�ؐ����N����^���'�m����q;��G<�0�Պl��+�b�`ޜKb��	�Ϫ�$��4,���*J��1߅�,o�a������h���!Ov��Ie�h�Xۏ���{g3�5���4'вAv�ߪn�����&���,����-E�Qz�8�Ȁ1�S(� ��jC@r���޸є�r�&��q�U>��_�I?�����PZD�_x./��<��/HS!�<u<���"�|�}K���wV��C6�|�9���w7-���I���2��CX8�u�4f��L��{{^m� �a�-P�ӕ�O_�����k�a���f���O�Tzz`��/����Lg�O;{ h�����3�ۜ��Ǌ<Q��Ķ�6n�iS,Ψ�h2�-���'>'�5����\ͱ8�<^�I�
#.�z�5y�bo�Ŀ߭	��TG.��)e�����}]ψ�Rh��o�z���1��HL䎹&����o$1:�d���O�1�}N��d*���5O�Nn�Uk�&T^|�oe��Wn˾/�nЛw�>}�7 {l!��.�+�LZ�74���/+T��B��z�는��<��tU�+S9-pyWl^PrCh��,�\_,z�RV������fZ����g%M'r��q�t�f�,WW�7B�
!V�$;)o�""B/P�h��CƫĬ�/v��f���o�	�7
�Z���KHȐ�-G�{���u���*{��NW�e�
ή�7����\@*�m��!-0-��^�E~	~��%C��V%p����'%]z@�<�`���l��RX����y�ɽ^�Z�}�5D���iE|z�5ar��]샗ȥ�4��7-�R�|^�L����s�A-�|��,����- @��t`fc�H�=	d+��ִ���"+Dn�l�3<��MV�/m��|~�=�S��2�.xc�Z�y#�D���nX,����!wk��!�H���뇠�&e?BX�|e��7����C_��=Q���*m@2�\'0d�<e����Ʃ��5�σ��������\���:�J�;�׺E�q;>m+�}�uX� )acZs��h��4�"���c
1G�.KLPZ+��r�y��]h�)8
n;@u�&g�����Ⳟm(h$g�4��5�t��6܇~PO�g���m��=�|+LC�䰶�����C�D�oأ���n�s�V�����Ϥr*,��7�H��#�t���1��B
k�Rf�N&*�<[d�W��cJ�,��"V������k�K�Q�-���'$�����l��nߨa��q���j��r[�Y����]�粊�)���6�L����{W�0�*��W6������i\4V?t'ty�2�sDlíDZ,�a�ֆ�5�_3i��h�Zz�(�6n@��x���Ð'F����������aϯ�F7S�;��G"fh�PײȜ6�yE$n��[FnN��
[�Ӿ�f��v
�qR���BS��**��Wh�7%M��\,еpLi�m�o��h��_����&`�e�����R[����4����K;�@ծΦ�*w@�[w]$q�����-ç�[2N� ��L��"g�Ŷ+nk�Az	8����R�EPM����ϊ���T�nͳ7Sc�!cRܸc�\�B��{ES&��;������̻!T�j?�Q9C�i2���bn�\��ߦ½����,��)rV�2¯�}zi�P��t�щ��ժ�s��M�����n_�#���6 �1ΐ�"�)u���A٢[]�+��,�+���� �B�����п��akA���9�OkVN���\uؖT��Zbvķ�z�7��mIO>��?hn�.BI�PQ
�J�b�Y��d��>�w�9�Yน<b�r7�R;Q��utF6��H�XV��m?3�*ўQ�$���N�6ߩ��|�*�g^�>�O뫓��?�v@����xlƞ���{�7�OwZ���6����NF� ���:�y��s��`����t�x�"����<���?J���jˤ[g������E1y;�o֒G<{�����6.V6�4L�wVb��1Eoű�jvKF^G����9�:�e-��gp����*�]��}������?ӏ��a|��4�7��4�J���V�P*�"r�JD�s�Sl�-��eD�\���؊!��~��	۹�����q��o�?����A�U�+At:�p�.��:5�U�����a�|FBab*��ߏ�4��`�{L�KZ�c.��'�*�'^���ObK�7���O]��4��⃢���0�Z��&��ʔ�����绺;����Z��7W̉O��0�/6�Xu�ѳr���:��a�$0�s�`�6Ѓz�(%ѽ�=�o~�~1͛s����[Q]��:0�t��j8��Ir������>&[��Y�	��7�	�	Q\%"�	���a�L�����;�M��l�؈�a�������⾐I����o��ϝ��NcOP�H㞱��`v�t�R�`��#~���m׷��t����Fid�HqbE������~��� >�N����@ly��S2�U>Y�݉�X�$�3YU��b�ġ8�+a;s��T�.�/����ɸ��Y���Z�.k+?(�#�U-�ϸ�< ��.Byȕ�jσ��&����g\d䉬��c�wõ#!���?��U1m�%Z�n���Kj��E�x*l}�E'�1u�ʽ�����Z+��M,��M�#�Yi���ɼ?b~$��}z�zi�#�faDl(�k@ul��?mC�
3R�|��dtn�]c��	�DX���|d/�ű��>��͢J�fK�q}5I?�0��Cڇ:����5���!Ll}{�ōm���$�Řw�����_�%�q�*�U���X)�f�`!���k�4ƺL{��W�$ ��� EX�2�����sI��hk�����,8T�x�Qrv-��jNhS]�r[�z�YO
(���*���|RA�ئG[�ܑې�F?*�۝��-�����-s쮾��_&­�F!u^���$?*T�ev�|��Y� >ZPG��[��e�Al)�
e���IK6�땎'O�#����
�(�U�J��+����e�*s��G��EN����8R�׼/{���.+kd1��	���U�N	QO��K�)w?i�z5|)ִk2��Ow���&?K��v�P���Q���8Y��XGC�������C��emA$-�o����;H��������>�5���6_'�HtN1�g�a;�6)�����t�l���cb,¯@W	�^��|$r�k��X_�&:��y߉�Ƥ�C\�����q1�5�.�[T�w-��>���t}�w}D����>z�G��l��	B�bV����)�'���3�|L�E��h�z6��%S�H�}.��"y�x�<ዑ���Ͳ�)��W��d2V~6�U{~�͆`���7,G�*ZB�$[��T|�l�,���e@�2��x6(q���jݗ��z�VMc�MԎ���J6(|��	�(������c�8��Tߊ���eˊ�yv�=�POyԬ�M�82ot�u�C4��ʩ��F���95Nه�;���%��m~Gǣ	��=������7Rn6���}ͼ���p�>�w�R�\?��X[xL�h��L�HE�v,Ox,;��3�'�b;(e{���o�v�۠��������z{��{B	^�~���E���1�"fG��v4��s�҄#gEtJn��*~/��I�&尀^m�玷=c�J�_7�_g��y&�}JA��M������_��vx�j�ܯ_��t���#�1�諞���AQ?3�i���I���\Q����թc&�I�9��mvl��yY���k$^�XbX�b�[�����u)��*c����Q�dJ�)���!��
�[��ܓ���Ζ��gOe&��P|��[�oM:<�Z���o�|:{�앆⦬�|Oi:��L)�^�(X^X3g�[��H���.ε	��;sr���`/�% ��VmtK�esr	|�.��B�r%�����??}��b��d�z�c;�i��xW� �ɧ�!֎çd��������8�2=������`�4|է:}tP[���eV���9��g�N_)xI�T���ث�5:9�s�kN&}޻���ڨ��z*���8����                             �w�[	��  