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
�������v����F+�w0.j*��=<Q�C"~����O��aF읽-\K7�M��L�W� ^����l�jo�jo�;��hoTL��_�:�틣Q6s�ϲ����}t�ږ����*�__�͗�'_���h/ǳ�8"��ӱӪH�:��r�,>�V��~{��|�-0����(N��rE)��W<ĝ�t=�2���q��C�,&}2<<����=]s�6�Ϟ_)�jF�}�#wҎ�ZK��J�t���U*��HJb<$'�prkG?�O[��{J�˽�]w �IVjSb�:�F����n �.��Y����l� e�׼�e.n��)�i�RKv"�IK��tI,���?��⑫C�7��;�y�l��Ow�h�������r�TX$��8t�{��/�������£�Cz*��ڈ���=[�*W�<����՞K�K�\UC<ߣ�3`
̅}[�
8��q�-��eZ��R7���T�c�xc�~R�f�G����}������bੀhY@#��ϥ�A���8����,K�����.�O���$�X�G
oUGK�S�j�Ҽ�_��uԭ�
�j�iuu'f?�,��]�݊��W�t�����,�1�2́A۽�2��=�Rq���Q�T�0� �Fשl�����pa�;�����,u���V&rf^ո*��^��h�W:\��E:7��A��)� |�� T�r�S��Q����)��=� �O��T@�N��!ߔi�~�v�����*�Xfe�y��X�L����3��c!�R\��y_VI��-��}����,JU|���Ԩ�~�yc�RJ���\dN�a{_6G�U���p��	Y�OU;E�S#���eU_8�΋�>aVj^�U�&����`F�{1��21��4[m&��T�L��X}���hX���v��2���n#�ux�A%G�4�(��9*Un�
��FB蚭�u�3i�D�M�Baf��� "Icy��_��Eh׈-Wh��եV1�ു.7�X�_�+df}u;t���=�%DUa�M�x�Y���n����k�ʽ�1�a�d�X ��<gC�Ϟ���
Mͬ���3�$�3TδW�/�$�?uՁv��p�@���9��U,�"�Bw�lGY�t�-!Ig]�uV�1l�U��ڬS��V�l�$�e������j���O���h�[qs�K��J�+���ۓQ�����9M���V���l9�~�̖Pn�5)6�d}��iWٶԖrI�n��.�9����� �XZ�&�"<����@uX��=-&}>FR=K�5c.�G׀�}�r3@�?w�:m�؀:-���˹e+ԕ�܄�:�S#	N�,�d������-�7�>`Xj�8�(�Z��I��P�x�˶[F鉱���W��^ʸ����<�I4S�yn5ϖ�W�dQf˪�Wph��J�hS{,�Œ3,������?�+5�^�S��s)ܽ6nz���<�a�IS5U�}L̵N�0߀^	ڭ�f��f�*�ؖJ&��S�����J��j��ݟ�`*1Wx��Uy`Z�x��9Z��nH�QT��9�x~�:bi�;5���u��|}������K�nm��Cx<�1?�h[����·n�R�tM'�D��l���2�)F��L4RhTN�O�\TC�q��܊rT�u��@]��ˬDM�K\��{|�m��w�>&��T����:-��>?���t��W��=Π��a�� aQ<��C4��C���&��I Jڨ �qa�o@*�@��s�6�@�6�k��`{yxhˋ����E)yP
[U?
��W3�9h$�Sב���L�"���" �6�s�0�U������I��]�P��f\4x{1i�R5�t��?�\�`�[D��5����ϯ�G�(|&|܊rP���ꑙ����$���Ӹ�"OUy��:�~��`=�J�ȅ�Yq?�JnuҺ<z-�ϽG�ő�����'�6�Ypb������OE��X�Nլ�6��eO���%������JF�0
�_Q��: V�]�W�?�M�_kP�����t��ې�^)�W�*x����\�X��׶��s`Q+}=>�
r��
߯?��I��1�(^��]�V\���;��-a���%�b�kȝ�����Z���h�"k�*�$/��؋jX�SFG�ç��"���e��_Xt*�6��K�g�V4 ��˖+Z�y>h���ㆡ�-�Kk�س�h�J�_t�����iDb�����aA\v=b�'{owwޟ�X��l��Uʖ�\F-)��YKr�n3�E�[ϵX�eg����1������ww1�5�&�:ܺń*�o;����>|Gk��M}�\��p��A�8�7F���l4X�O������4�6�Ea�5��7��k;^{�{�`����J��7�M�}�E?$eN�.�|V�R�xO���9��a�GR���V=B������g_@Ȟ-9�x\�K_3�[��m���b��PA!��Z��t���h�	�~�|��ܵ��S�aW0~�fV��4S1�v|�������u�
v���6�,b[��xJ�s��!N����w�aN5?c�$�H ]�D��~簨�Еg� �Kq�{��\�¥y�x�⡌�V{-�Q�V�۶).�[��jޖ�'�h��T�9՛V���y�0-��'Ř�
w]R_�07���cg�5��J���\*��T�[�ha���E3�Y;hs�Q׃~�`���j��[���P�j�MCl�RQ׾~�_m����R��|vU�Wa�*7�ؘ��{�rueæT��1�ܼm��S�K�4��.�F�wf�F�B�*_��[�\e�3�^զGi��ۚ��ȡ}'9ƛ�Y[�0�?�z�!��}<��_�A�=}�}X}�VBO�>�jҸWe��^����}����~�Qse8tw����IO�@�b���/����3��Z�V��J^��&Zǰ<�}��E��٢��b�+l���OO@�M?B��H�LI���4Eq��#��V��2��{f�1���B�3����[ԧ()~�g��>}� ���翷ekUr�R�=��\����,0䤬ϸ�[X���䶶�Ealu�պ���D]���L���z�77�4�����sS�?_[{�����^ɂ�;���U+x�2J&��\�cD�u	rjM�����:���rj(�X
�t��[-%�
��Z�(f�Y��?� �|�\v����ơ]� ��Hq��<
]�V�-�ʿ�*a�N?bP��%h��/�]��R��5{�q���.7W�O~�x�#C�' ��3��:�z2�b��?������\	�j��[�������]�l B�������Y�)l�N��{�	Z���}�Tuy�_F
u��Q�zz�-	�9�qP�^Zz9,���L�K9+�]?�+��+����d�/���b�р�i�K�#���VD���[i�{���/G�n�RF��:�.'��̆O���ԓ'|&z�#X��3�'��m��[��EٙLޝ{V�P�5�֯��[��xJ��?L���_�������������gϟ>��w/�W�gA�z椗�^���e<�GK��<�+��g���>8� Yp�FބB��+�_�Oߟ�ĩ%����z�l5��c������C��[a��u�%����~�N��$�*A�l���A�t�	{��]Rle�C(����E��Bc�~�}O�������;���m���0ca�_G��<��c`��\8��mv����9�86`i�쫼&�t�~�M_u��m�=�?x3*�T��Eg(�� ����l�������5��9��--��qT���%��ֆ����<�Lo=@�ꉟ�������Y>'��K��F��w{�)�����h���7���֞�x�����f���H���;Ƶ�#qo:\���0����u��ǽ�w���sz���yě68O�����K0}��*��u��Kv�u:������>�C����f����9�n���˜T���Of~H t&>��O���I~ʂp���<}B)�ЈY�r����,��}h��𚅙���4�bl���#�F|�0��w�AppG��Pl���I�@ʠ�9(�����o^�&б����m���w�+0Y��pI�pO�.�r�Thl�T�OxA�(��м���r}����t:�\]Ex���R7 0��a�OW'��$]u����7p�i<��ܿ.��O�0%�b�ޞ�L�}�����agY0�V�V�'�2׉|��V�&rX�0�?�Ӹ�)�x���r��Q�� �0���@J����N���Uq�'���H�p�!5h�d�����AA;ls�Ν����i�Y�0�{�	�t@jN��t����v%#�]�d�*��_��x2q�iv��� 5���0��X􎴱)68�d��_~O�)�8x���S��� �Va����A���'ԛ���ɷ,D�
�����u&g?p�`��Ƒf?�o�opT������k�Q{�>H�B��8��-~9iЖ���g�v�bB����R7�����`�&l���w����^�*dOpC�@yB�Ag<��o��:�!WHG#�_��T��_$�w�b��+��=q.�0^�S/jI�4H:0w�8�Ho�5!a�,D:U��fD-�e8ϡ*��@k�a���1C\t��^���XalK�J!-ȂG�h#S�H;��1�a�{�Bu���0���#�o�ؗ��	Ϯ�bG�0N��a'�qF�b��y��ze��p.ߑ��So䮯pJ�qZhw2pa��G�č�}���V4�3���,�x�pN�Cg��u	��,�A2cF	���NG���Σ�m��L�;�>�e
u����&�������@&BO��р@Hx�b8L|����/>�x����2ı7�	O��spSĈJ�rȫ�q]�g��k�@�&�<�3mk_;�(����}� �$����Q�a;.��4
πR�Ľ�7�_@yx��;�.�|�XDC֥\h�.��X�
�_�z���c��`�K<v�8��Σ$�I_�y|�#����E��M������ ��2��<\�r}tLN`.%��\4����?���� ��NX���^���M��3��M8 �7I�$��Ȯ�����m���;x�Y,B�i%)��Y�y�����0K?�
u��\؊_��,p��৤���)
( �)bPիr�H}U��r��z���pEĢ���5��}���YЙ���W{��O_|]��=}������8앪�yl��2��3ߜ����8��w�����~Z�|�2�$ɖ8W ��/@��4f₎�"��YYa���a��Ah�:6s0ެ�����{�����,�&���ֵcG�iT:q�D���@����@��(�|�g+�}��q*Z� ��*�BCr�)@�0���#���(UC�Ac�J��_�d�~��O�}��>�����(��>����S������8�����v�m�|(J�ń���;�qfS�8��	?��n�a�"�W6%�=���ӆuJ�]t'�����O(�i�����j
�2��%ߦ��2�ou�:I�S�u�.�i��c���P?C;f�f���g����H����S�c$�Oe$$E����u��ɥ�(��/L���${ǃh �;&I��9��8|c�B<�͘��X��	�do�@H��}m�.v�?�Qx>aO@�J/���,2����2Q�D���b(�/��0c �߼`J��3_�)k�2+�b0�)F\����9�[/���>�z�Z��|Z��67 ����Bu����E�1&W�Թ��(u���rh#�B[e�F���������O��3K�TAam�o��k�R�.��T��~���lR��<g�IФ�Ⱦ��oi��<<����<<���	�g �  