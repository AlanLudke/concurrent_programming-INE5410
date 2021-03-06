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
�      �<�V�ȲyEG��dl�	�!�$�!��I�FK�m�[�Hr��1{��y:��;U}�ZrK��u��+ARwuݺ���戆�)�����,� �6����6k�S���fs��\m,?��+�����XJ�$����ΐ~r�|�Y��GS��������rs���$e��<p�����F��ݒ������i�'++O���/N���{�t�zK�N8(�;�|�{ر_�����;���z����)q=2�K���!n��yB��wR#'-�e��*Ћ<gī�]'"ƼJ°*L�;��q���n��k'�3:u� p��#ǮwF�c�> D�Q9�i8C����:)������X��n��
���h̴�Z=k��'�{��������{[���=n�����H��#\���8,�]"�g�~�T?oV�i�O��m��(.Y��y�ۗ��u|�3旎������nf���[D�f
�ҙ��f���d����o���,} ����	����')k�g�ӣ�sǍn��,�_]���f�~o�w�T���������l��o�����/�{w����J�E���|s����f	��z0��\����A�z��7Y��P �pa��@8�tL�e���
��و1 �Sp�h�hŁ�*��a��ϏtH"wD�IT!4���z>9nH&#2�']qq�-�L�$dɰ<��8���g�!h�D������~p�f�G�x�$*gh>���(��Rb�����HVG48��m����X���'OV���N�j�����m{�m�E ����F��"��g�1����þv��u֏���$b���O����Gӧ�w�t?aR���WA�6t����q.mB�#��d�l�3�����9җ��� 'h��܀�R<9�Q���z1-����_��ٻ���Y ^����1~�嗹�����"4���L�O��[��uz�m��H\���<o@�I�1�o�m3��pa�4%�Bݲ$�i�~[;)��b�� 2�(�	�,���U	eY�4���(��.K�`�g�@�ݫM�ʶ߿9�I_����_�Ԅ��:�
�*7[)��4Բ�|
x9̓����A@j7��c̻�%�jqlA��Ɣ�L1��4�2�J|��rcGJ�|��K���)�IN����^�y� ��8p��O��G����Q!�ҥaq+5���hj��7b�CCD�����) b�0uɭ<eaü)� ���å��Zmi��G� )G��㔌����s"?��y��[���������:5�o6���w��ܾף}b���������?�;�������+��m����͇(͹^w8��S���lq���s�t��A�����ѩ�zn�Hw�e�F�U�軽4xJ���J?���A���s�fϟ�� �> L7b�9�!FaF!�Z�^������9	�F��Za�ϝ�;��F(���3�[�*��?63�A����� b��G@�;��xT�Qdr��w:�3��;/�HC���0v{&��B�EL׀��.e_b\�$�+�A���#Į��
1J#;�M�5S�*C�ڡ3�d��L���8�PPU�ρ�@sJ�`��݁;��e�n��BU��Se�Hh&6�;AH�kUTU��ڨ��,Z�L?��l�8Ŵ?�J7�		g�e��E�K�\�S^��o'���[�Q<�כ��O�������p�vB0�(;�C�?=���t/��3L�M<j��FN4�Լ��ɤrm�j`8�c��y�������!�N�p%�Gn�������~��F(�5�v�a��!���P���Ӂ� �!6��cuX��*�f�P@��7;{����Ԟ��vOTNj��֞�y#�(j��K5�@@�#��}��"5�AYЗ������y�H�A�<�Z�jI�xEX��Iӹ`T*Ec�}O�N_J�1F�1�o�N�:I�%6�a�N֤p��U�L����T1�I: ���KGÀ��)&G>��y��hL�I��&ƅP�L�H�e�R��D�g���y;@iw|a�
�b����CK�tf���0�\�ؗP!.ԭ.7��Dch�>D"�{�>1bU�Lc(��8Ҏ�k�j>c��P\Ѐ4WǲF�����Z?6���"�g������t-PQzF��K��(E]��k��eH�q�7�:�qtb��4T�` V��	�0�Di���~&5�&�ͥn��N�L���$�ݡR3��u!�=�RH���O�8V�=�A��D>���,�*X!f,m�Y]l�eUX� ��5R\�L
�����H���
�#|	�j��<\'?{?*�)���5�JTY�/�k��k��H,�!'��ї/�yy-]���x4���Q��VW��Cq'Dq,� `��(���N�:���u�;�g�Bb�Q�-(�
��S�$N�}�G��l����3�"ɘ1""���]�a%�{����n
�i�F�($ԐdtކA��97�Μid�I�y\E?�+�T����.��,O	�م�(�0��:��`��S���2�u�)z��s쏣Pg9z�Y�*����+=Jrf�q�e�Bf$-l�.Fg����b����������V� V��d�PX�b;����!'
� ��ޗ#���<C( ��	��G��l�XV7���Ұ|�qt�$-���u@y��J�:M�EiXC5�4�^�Q/���Q[X'*pU��q|�z��\W�i]����5�{��X��&N�v �&��ƾ��kN�ϳ�T���'J�0��y�H��P���w{��6�^Zj����v^�u{�= ��t)�7`�V;�lv�bՖ�";����i`L���x�>y2���?�]S�ۉ&!y�+�5���Y��ٿ���NY�O�F#�������z��+_Q����k�^�֛�p��O�~ Q��o�?��(��Q^i�M7�K�����"�g�8<��O�}+5���si�9�1�$��ꌿ��F�;f+�+q�Lx���.(��6��2!k��1
�ճ����*�U��w~�����������
i4��12Zl�+du��
_�ŧ�أQ{Z!+��O��h���h<[�G}eE�ZY�5 `y��rO�|�>]eĿ�����X�:�l�>c�f�R�}�L��g�;�d�O���Z%\���%z����	��P���I+u<0q��g�;���4����'&@�,, ?�x�ɑ{"�B��f
{ػ2r �c��L� �Cwl3���(bo��Y�K'�R��2;(���5N�P��/ŘY3�?eO����(SfO���<}���7-�¶�6.�����6/Ega���q�hz쎩9[W�m�;�'��u�����0�O+؊�:��C���M�u�g�E����@�*�|�	b�O�ٕ;�cU�j��I�Y���V�Ҳa�n\����4�����9P�
P0n5�������iV�@�Hb�	0��I�8o$VLMU������ �����L	�L��f�?V�0 5��n�c����?��o��u;{�3�-?y2u�sy�����$���x�0��W
�����dw�m&�b�rH�����s��6:�QP�����,ṙh���GF�������ϩ����k�8Ԛ2��_�~ ��v��O܀fr:t>ў�cX��=g���t��1ڮ��B����
SF-ps=pH�E�g9��l5����L�)�����Z���P0�!:j\���D7Bqy�Jy(d��O��te>�-��U�q'��%���"����v����t�.kM���|V'e�|A�j�}�:!�h�n��|��̪v_��1�wd���F(0�^3��^��h�c+�B6*r�̿18�\oBg���$^�iQ�9i���6�WC�^V�j=�@�p��̲ժ�X�ub�������:����G]�'��>���_}�1u�o��>���i�lӈv#��$tÈ�������+��ȁ�I�NH¯��aH��0��� s<��v�Vi��iou����������W<�;1�G��������`��:ޱ��L��x5�J�J�� �tl��uyR�#����z�e�,qCsdL{,{�f�=]~p��eדB:�����΁��I�o�%x������L��ys
ĪT�o��ϻ��˭�+`x7T�@���#������U-���a��'���ؼ����*�Np�z:fv����<B�����/�m��a�~�������)��������[��F����lw��,�d�F���=�u*���4��y�keu��w}u����E����t^�7�s��j9;mMr����I�f3!B��+}P��Oðpmn�鋒()]�Qr�7KU���ʉ2TG��L(њ��瀵G��%g�pHlYDfGh�r��:�l�p��{jG��W���NpV^��Ke\*,/a I?E��� v� r83�6�Jzba2S8�D0�{��{{���)�ӳ�����c.�C�	DP��9�3㽥��a�)�4 !���}�҈�^l�
M�wY@Q��S�k��9D�M�$,E�wD�����D���x-,�f& *(����	m��k���>��_�u��J�<M�M�z�������Z��;��f����������z?�������X�2b����w��a��`�w�gn'L�Sy:`�0���Ͻ*���#v��
��
�c��[���#مuC;��I�i���W`w��'��I�+�Z�#tbЊ�ܣ��[uÅ���o �x�z}�!i��܇��-BET�F\@�Y�_�\�"�0�\s�%�HʗS�9�a�5�3;w@���"2��P��yD��J��t��?�;ʅDN�����.MdZ�3��^���߳/;�?��>h�X>�aqv�[�,��o��E4�Ë��w�Sw�%����7�m�T �,J��=/pmJY�]@���u�0��ɳ�؄A�$V�S�=d���f~r;꠳�m�n��������7��Z�?�������F�G!;��I�����r3�7�'B�0����x��ʑ �H�0��7�q�xao����\����Ł�kK~�st�����BB��\�G\�TזOy <-"�*�;��5�8xŃ��MK�NX�O9�1��ر�Y2fa�'���L}��%�r($�3x�a���]����X���eJ� L v��ݒ�iH����b�2U[��mH�EȮ%´N�m�ۉ*�\���No�.���s���\b��;p-(ߐm��^��
n=\��e��DV�nn'���V�y����YP.b[Y��A�*�܀1�K�V�q�q���"t���8�!]�J�Ift�0�b�8�f��H�03y�2c�8�1-#�F�u�7�Rm|�![7��Ue�y�mj��Pv��b���V���`���%;��[����Oŗ�Y����2y��
QK&wH�s�Suu�n"�VM��&c��v����1)@���+�/���P�0޹J�W@��8+o���i�Ӳ�cr��*�>:Ѵ̅�8���X�i��)�U%�����G�Z�EP�*d�]�t�Ze�Oގ��wx�%t����V7ԥ�4��������H��H�����&OƹK�Q'��7
fT�5Sa5�[,L��,`1��ǖ؂���U��Ԋ�ؚ	�Ja��Z��������쑘�n�l���`��p�`�BDʙ��kF����D���!
�������v����F+�w0.j*��=<Q�C"~����O��aF읽-\K7�M��L�W� ^����l�jo�jo�;��hoTL��_�:�틣Q6s�ϲ����}t�ږ����*�__�͗�'_���h/ǳ�8"��ӱӪH�:��r�,>�V��~{��|�-0����(N��rE)��W<ĝ�t=�2���q��C�,&}2<<����=�n�F�Ϟ�h)�0TfF�co M�^��x��-�$'8v��$���Nv����i��Sp^�U?v�����f�2�� ���ȾTWUWWWWU��r*�p{|m� e�ע��w|	�Z�Ԓ����>w����Ϫ>y����f6�@8ϧ�����M�=�bu�_�[Ξ*��$5��B��v���k�6�78�h���Ku��6�&�d��ֆ�*\�����s�qi�U��j��{�{,C���o+P��;:!�5T8X����*u��m�M�<&�7F�'u�b�|�������w�z@j+(o*�
��4��\jN��0
�/�t6	Ҵ�����!��+�H��h)zr����5%�j%��n��PPW�O��{1�9`���� ݱѭ��xQ�.0q�h����!fO�90x�q��������u��ڤ�F1�x4�Ne+Ľ8�����i�4U�g�+em(�2�3��UAl��yD�����,ҹy��mNY�k]��K�Z�O�r�WNOQ�vt�?پQ5:�n�|S��N�M��bX�4�b����ϻ��"Pe�u'��'����r����b��%򝶥R�/0��u�� �RU_��E�O5�Ya�>��汻W������ޓ�͑pө`!�b�B��S�NQ�Ԉ.ųG�fY�ή�"�G���&Aի	�d�r\����`�ǔ��P�@���j3!���f"���YU�F�B5	ڙN�h�N��x����͟ҘR�L�*4�T��*$��%@�l�#X�0��#�lj
3�wnI��C=n��]#�^��W�Zň���܀b�N|���X3�ۡ�GlW�),!����h�����p��o\]{U�e؏y#�Qc���Q5>{�P�*45����gPHz��\h��_|I���᠁z��s��TL�"�Bw�l�Y�|�M!Ig��u+��c�`�V�Y��i����I��.��W�����FP<M��ң)l�˭.EK]L�����/G�gG�s�0=���1��r�'* �.�-��RkVll�����,|\e�-�+-�i/>����.�����\�biPh��X��H�.�aE��� �b���J�5c.ȣk@�>_��П�E��{l@�ytw��Ҳ�JcnB]۩��iEA� 
�Qm�Q�^�� �;D�	0,5a��o-H�$�Y�S ^�k�=���XKǂ���_��e�Gs�zh� ���<���R���,��J�y�F��@W��M���Sΰ ����,���<���9�Rxx/l��*Gyr���j�\���k��a.���[����̀TD�-�L������o������*�??�Tb��r�� ����č ����4�������s|���u���Sw!n(���$F������w����6#��x� �h[�����C7|)4�ҙC3���6\SF|3�H��F.���蓾�Pk�q�?���q]u9P'��:+q��gs��_v�d�݃��	�v&��k�N��l���%01n��oh�3(���`2L�$���a2��C�!�%��M Jڨ �qe�g@*�@��s�6P�@��`��<<��EEM�TҢ�<(����ZQ���ˉ4�)�����A&��[r�	P�9i ~U��'.(pRf�Fi�&Tj1���L�TM�.�������(�"�o!���O_=�QxN���X�Z�Gf~��
����qjE����u$�pq#�!����6������Fe���պ<z-��g:�܏'.�?�c��?tH�|�g���Zʒ*�>�j�cQ;U��P*�}<�����H��+�v�d*Mi�(@~A�w�$��-�վ2����}�D�ڴ%fO�;�߆\e�J��M!S4��u��b~辶M���Z�c��qV�;�U�~��2Nb��������b��~��	��o	��,�+f���Y�(��U���l� ��SA��za��^U�2��2:j>��n���-�/k�w�j��[����\�?��� �}_�\�Jg���!���C][�Kk�س܉p��OJ�*����B�Ԓ-4,�ˮGl�������۳��!�ܤl��˨%'8k����m(^T�7����OK��Nc���݃7AR��v��nAP��}	jk?��h��B��i����;h���I0&#����2~+���|Q�jM���M��ڎ��^bk�+E���f3u���I�)�e`�g�+U��Ԇ͙��k�=�r-�Z����O���}A !{��hj�q�.}�oE����2x�=NC�(b4k=�����'� Lp��������uTu���B�k6��Z�A0�8b�G�@�{YO�n�YHR'�㡀WxKj��"�u�g?��t�0���}̩dl��W	��]���(��9,�-t�;���z-�!�n�ëX�4��lS<��j�e� .��m���&"�������6��?�vA��$9�v5����#Q"T������ ���7:��Ra�����
Eu]/����A�S����{�=W���r�e��^�lb�������j��}�z�泛��
�V�9�ƤT��{��+6�����m����]��)mw�4R�3+7�ojU�zު��*{���6=J������E��1�t����3��ӯ�,���z��!h��w��o��J�)���EM�����K8���/�[☣�ws�`���nP�Z4uTd-vY��2Q^�^=S�,�Eo��l�E�j�u����Z����-��-���a*������=4�y�͔�ɟ�S\Άh@0����ݘϽȌ!�-�ڞA�'tܣ>EI�+m�ȴ���C���ך���֪�ॆ��\����,0䬬S\�-,�Jgr[[vjQ[f�.�n2Q����.���S��?�0M��?�ꙹ�?��Z���㩽�W����W��˸2�w�J#��sHPRk��8���3	��g�⍥�LG߬�ի�R!9[� ��iEg� �����Q���qhW2�'3R��1�B׾}�_�T%���{j�?���"Rㅻ��U�=�e:�[4�����F���+��А}���~�uVG�c �+F�C���V}y]]�+�[�_vk��}Y�Y�څ�"j�a(��e�M|%��Щsp�D��0��ג����k�p�A���q�[D��qP�^�z9,���幤�i��i%~�?6������YX��@��$8���!�5��J{?��x9*vC�2
��Qw9SGd6|�M����SR��:�5<3{��O�ܖ���]�]���y%5�P�o�����OI��C��+T�~�����m��t��鳯���gy�Xټ'�nzݑ�X�]�}y��(��bkd�b� `}��#Al�M�q?r��2�:z{v��l$N-���l�曓l<ƺ�/��8
n��ұf��P�[P����?��e�Tib�0uS6M�g�o�^C�x��l�� �~�l�B�8�0�1t<?���}����YW��倜!f,���ב�z,Oc�أ�0#c;��!���:�!�F�E �"�� ��Qg��㓣W'����^��*��q|�ȿ��-��9>�����p����5�¶Oس-��LE��0�`A��4H�_8Ha��YN�5�n��ߚ���O� r�<|��������?,���x^~{���t$�|e�=�Z���7���X�hD�$��u׺G�N�{tq�9=s�t�0��/S���#��L_���&���%;�:}���	>�#�����������~�����T��4H�AD+@�N��O���M~��9H����`
}B)��ЈY�z���"	�i h���E����,�cl���#�FXa�I�����������:HRE/Aa� 5��}��%��m�����i����/ r�
z�%��=����{נBc�����@����]����ہ�׳�tgs�D��O����`�9�%���݉�}7��}������U0	��M ɱ���3\���_�����o�E��͵����I湓 `F<������,q�������,�p<�u��<7�a)�` ��,H��J���X�ҁ�3����w�"�˱�ܠ��E�/:�����tߓ���FT�1�{�	�ta��������H���*�џ�r����4��]�c����x�b� zG���2��]�O�/�)�8x���s�") �UأfQ����	�&"�`�-���"�n��g�q�I�.1,���8��G����������`7j/��XȰS𚢅"H&n��eiv�����ïh���M�h-zXe�)[����8��y�B:B*��<�z��y,}�Я��B:��#�8��/�EJ x�#�._A�ݩ{����zQgJga��� )��Pj&B�$Y�|�����f�-$e�̡*R�@k(a�/)c8�8��jG9���־�J!/ȂG�h#��X;��3�a�{�Bu��/0�}�G��8�q E�]��'�Q��'�N�����~��Z����GZ��'75�Og�������p^���;�{0�Σhˍ*}��d+�řw偊�^0����݁�q^��x���̙Q������8������� �M��Ov�i�B�q�O"l�	}��6Ƶ��+X�'��h@ �x�d8N��@�����"���e�c�����⦈�P��W�Ἲ$����t���y�G�֬�t�p��1���]���%�	�`���NB���g�����85H����B�8� y��ռ��p�h����s����*��i�����G�w��m0��0��v�$s`�C��<J"��D�����2rȍ@<\e���Y���~S����j�~���M9?:�$0�`WN���*���y��,�j��O"��⁘߄z3X�݄��5��(�C� ����GoOw�I�:�VJe�o��Vpm	�e�j���tl�o�D�s8�)�l�q�0�1��U�����ʚ��>��n�/W�X\dk���>���B}z�>����|]:�}���r��9��W��w=��9��@���v�!N~Pd��q|ᎇ�����)�=��������!>w�Z�@M�R��?^�A������MҀ"��C&l�}Þ��[˭�j ��p��;��5�t� =�)�;�.��6��&�2���Bm����Լ1� %wFaiy���6L������d��L愯�V <s*��i��؅�C��=�C��.�Z�єؚ�n��ҰRq[1����TRn[���"��0�W�����@F�>.q�R,@��ǾӜ�h�W�R�DľҸ�҈����ɟ�l�~Aue)i&��h1B���V�H���T��y�zV6-3L���d&h��V$ۻYZ����Y>�g�,��|���Y>�g�,������=� �  