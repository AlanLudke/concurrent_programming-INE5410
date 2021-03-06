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
�      �<�V�ȲyEG��dl��-�3��5r�9�`����ڱ%�$����~���	��S��%�d ����^	�����]��7G4�N���/<�f�iuy�������A}qiyeee�Q�?��K��d�۱��q9!����p���CS�����������}��Iʶ�y�����׉\߻%q���R}1��+KK�H�v���y��<\8u��S'��l��=l��wv[������z����s�����I�~��G��,!U����&��ԃ2BX�E�3��̎cV%aX&����8��k-/�k'�3<u� p��#G�wFfc�> D�Q9�i8C����:)������X��n��
���hL��Z=k�������ER����������}��RH���r�.�~|����3{?r��6����2~[��%�KV~|l����lƌم����qö���)��&��u�B@�pf���m�<���y����$K�#�Ijf���i�I���Y�ti��q�ۣ1��WW����r�qo�w�T��������mo��o���k��.�{w����R�y���ls�����vR�`�����O�,t�o<� ��@��,�)#�p@��2��9
I>��c@�������3ЊU�����_�D���Bh8���u}2tܐ��d�;���<FZ^��IȒay*�qr%�%�m��C�*�(%UGU5|�B��S���IT��|t#R�QN�%��2j����?��ipF���cS쿱8a�++K��'I��ҋ��햽���" ���w�Tb�t��P�~�a_�a��:�G��h�Ƀф���P���Q�=u:�0)�T�� :gt���8����!��p<�l6�������KN�o�4Gan�_)���Ѩ
QSD����`�Z/v����Y�, /Rm����������l}� h�`��#uR���g�:]��up$�W`c�7��8�ŷ����q87k�v�nY��$G����צ1�[ `���pQ�	�Y����,u�V�Gq�wq��R0D�3}����&Ne[�^��/v���/FjB�pdV�a���TcjQe>����AV@w� s���p�1f]Òs\�8�
� dccB\��F�V�@%>Iw���#%\>~�%Y���$'��G@�r΁<k�y�^�#�ƣ�F�بF�Ұ���?�iz4�F������!��|��`�1�����V��0�a�O�]�Oȏ���|���p��e�����ۇ�qJ�����:�T������A~ei)w�o�N������;I3n�����������l����a�Yko��ҶK3P���C�f\�3���)��Np6��H�~:�ṕ��Y�����v=7���w�2�{��,}��n���aj��L��!��[[�9^��Oa�g ��������?ÐvB-J/�	P`|܉؜f#�t�0�G�N����?#�o���-A�[�����pIA}1E�#�?��gv<*�(2��w;m�ә�Ý{��iv\q�]�Y!�"�k�
�n��/1�i��� RT�WD��bW��p������)E��}���T��~��lp�e��*�g߅O�9!}0��N�p��2{�L\�*W���U$4ꍜ ���*�*admTLe�x&��x6k�bZ�A�}����ͲX��^��r��)/�ී���έ�(��˫�+�������p�vB0�(;�C�?9���t/��3H�=j��N��Լ�ɤrm�j`8�c��y�������!�N�p%�n������~�=�F(�5�v�a��&���P���ӆ� �!6��cu���*�f�P@���;{�����Ԟ��fOTNj��֞�y#�(j���K5�@@�C��}��"5�AYЗ���7��y�H�A�<���jI�{EX��Iӹ`T*E#�}O�N�K�1F��o�N�:I�)6�a�N֤p��Y�L����T1�I: �G�KGÀ��)&�>��y��pD�I� �&ƅP�L�H�e�9R��D�g���y;@igta�
�b����C�df���0�\�ؗP!.ԭ.7��Dch�>D"�{�1bU�L#(��8Ҏ�k�j>c��P\Ѐ4WǲF�����Z?6���"�g������t-PQzF��K��(E]��k��eH�q�7�:�qtb��$T�` V��	�0�Di���~&5�&�ͥn��N�L���$z��R3��u!�=�RH���O�8V�=�A��D>���,�*X!f,m�Yl�eUX� ��5R\�L
�����H���
�#|	�j��<\'?{?*�)���5�JT����k��k��H,�!'��ї��yy-]���x4���Q��VW��Cq'Dq,� `��(�����>:���u�;�g�Bb�Q�-(�
��S�$N�}� G��l����3�"ɘ1""���]�a%�{����n
�i�F�($ԐdtކA��97�Μid�I�y\E?�+�T����.��,O	�م�(�?3��:��`��S���2�u�)z��s쏣Pg9z�Y�*����+=Jr��q�e�Bf$-l�Fg����b�ū�������V� V��d�PX�b;〮�!'
� ��ޗ#���<E( ��	����l�XV7���Ұ|�pt�$-���u@y��J�:I�EiXC5�4�^�Q/���Q�['*pU��q|�zs��\W'i]����5�{��X��&N�v �&��ƾ��kN�ϳ�T���'J�0��y�H��P����{�/7�^Xj���ow��uk�= ��t)�7`�-V;lo��bզ�";����i`L���x��>y2���?�]S�ۉ�!y�-�5���Y�&ٿ���NY�O�F#�������z��+_Q����+�^�֛�p��OF~ Q��n�?��(��Q^i�M7�K����>�"�g�8<��O�}+5���si�9��$��ꌾ��F�;�+�+q�Lx���.(��6��2!k��1
�ճ����*�U��w~�����������
i4�12�o�+du��
_��O��G���B��W�,�c�V�G��*>�KK��|� ��Ok�x�����U�@���+OV�c�?�ry�){,7.5�Gȴ~¹L��t`�J�Q�e�.�^�W�:A��0� ِE�ܟ�R�c��p/�s�lLsY<~b4�����0�'��'�*�,pm����+#P�=���~0 9t'�6���"v��պt"*e(��"�X�u9�R��5�S���@�
� �0e�� s1����_�i�ۖ7ڸ���˫m^�.�¨�Q�$���Qs4���[[0w �O:��+�K7
a�V�'u����T�����f�"�c���{u�rUn��Ī�(��+v�ǪV�\c��&�p5G	$�T;�e�$&ݸ ��i60U;��s�.�`�jx��Q%�Ӭ
���b`J��Q�:H����-��u)@r	Tqq��2��1����a jBm�`�"������d��v����Z\Y�����z��N���W�M�w�+P��NU�;}ʶd1|9$�����}��6:GQP�����,ṙh���GF����#���ϩ��F�k�8Ԛ2��_�~ ��v:�݀fr:p>Ү�cX��=g���t��!خ��B����
SFMps=pH�E�g9��l5��L�)���������P0�!:j\���D7Bqy�Jy(d�Џ��xe>�-��U�q'��%���"����v����t�.kM���|V'e�|A�j�}�:!�h�n��|��̪v_��1�wd���F(0�^3�n��h�c3�B6*r�̿18�\oL����$^�iQ�9i���6zWC�nV�j=�@&p�mO�ժ�X߶c�&�����:����G]�'����)�_}�1q�o��>���i�lӈv"��$tÈ���:��+��Ё�q�NH�/��aH��0�� s<��r:Vi��nm�[���������W<�1�G��u����k�`��:ޱ�������x5�J�J�� ^�m��uyR�#����z�e�,qCsdL{,{�f�]]~p��eדB:�����΁��I�o�%x������L�N���YsĪT�o��Ϻ�����+`x;P�@���#������{�U-���a��'���ؼ����*�Np�z:fv����<B����[��m��a�~�������	�_�����7[��F����tw��4�d�F���=�u*���4��z�kiu��7���������n�<hmn�N��rvښ<�P]3c��!�fB�(LW��:���a�����%QR����o��t�e��Fř.P�55�k�N+K"0Ύ���ز�<4̎И�d=u�0��6s�Ԏ,��8/��଼ �ʸTX^� �~�(H��4�%@�p:fm�9����d.��?�`��
�)���;b�Sn�g	I�;�\��d'*��`'r�g �{K���TSBi@B*��#$������r�Jﲀ������33�
��SIX��5�
�P��B��
O�Z,X
�L T&Pt-<!;�\�����}6C��&�Jy��T����)���Z��;������˫�������N���S<bʈ��:�ͮ�鮂��	���0�N�}�������>�������9?�,p�*���nY��d��v�A�~�I._���Ǟ8�&ݯ(jj�ЉA+
s�Z"n�2ǟ������|���բr�4Q!q�'U~�r��T�|r�	�")_N=�T���P����el2�pȜ�S@��q��+��ɖ~O/�(9��n'�4�i�O4��:r{���z�n��@���u�d�|����x��Y>�%�� ��!�h�C3蠟��YSR���ׯw[0�@PY���{^�ڔ$2߽�<��/+��%`�3(1�g)�	�8I����{Ȉ�����v�A{w����������6��Z�?�������F�G!;��I�����r3�;�'B�0����x��ʑ �H�0��7�q�xaw����\����Ł�kK~�kx����.�BB��\�G\�TזOy <M"�*�;��5�8xŃ��MK�NX�O9�1��ر�Y2fa�'���L=��%�r($�3x�a���]����X���eJ� L v��ݒ�iH����b�2U[��mH�EȮ%´N�m�ۉ*�\���No�.���s���\b��;p-(ߐm��^��
n=\��e��DV�nn'��)�V�y����YP.b[Y��A�*�܀1�K�V�q�Q���"t��8�!]�J�Ift�0�b�8�f��H�0Sy�2c�8�1-#�F�u�7�Rm|�![7��Ue�y�mj��Pv��b���V���`���%;��[����Oŗ�Y����2y��
QK&wH�s�Suu�n"�fM��&c��v����1)@����EYW�^�\����+ �*�
�����WsZVtcL.`�U�^�G�#�􏹰��+v"�x9%����:}�y��Rkè�V�,�K"�nU�L��۱�����|c��C�ꆺt�ƛ��#�~���ɣ�����d��8w�>c�<�ℝ�F��J�f*��r��ɢ���,����[���@���*6�X��SQ)0^�}�~���|_�=��-}��ZL��,T��H9�zŨ0ݰ��HQ:D!���1Ó��n=�u�hea��EM����� �qHį�#�[�I�<�������k�&�	�\�������1�����_���a�`��m��I7���UǱ}q4�f���i6զv��X��|�<7V���˿�2���_]��x�� G��}�r:vR�]gV���'cӊ ��o7���&�\�)��C�(e����S���U�]�]9��u��ŤO��g�������MqI���� ^�}b�W����p�8��\��JZP�Zm��&g?&��.U�)u_������gF��F/ةJ��Ĭ4/=�====�=�ͩ@���� T��}���#Hx�ꅖ�L~����X.6e~���#g�N�|Sw��t����Є�cKFG�����4�H.HR��},��k���j����TLj#nr
�lm�X�+�\ޗ~V{.4.ͷ
pe�|�rπe(0�m�*�xG'$�v�=h��
�`bhS)��z�M.��:^��|�������7�z@j#(�J��4��\j�O���	����$�M�8.tyz�{,i�J5Rx�:Z���2��iM	�Z	�[w1���S����<6��]�݊������	�\Y+bvd��o[�2��=�Rq��Q�T� �} �F�*m�����pa�;�����,u���V&rf^U�*��^6�h�W8\��E:7/�A��)� |�� T�R�S��Qnv��)�Җn�'�W*��N��!ߔi���v�����2<�fK����� T�6E��f�	0�B�9���B�~_�-��D�ӶT���w0.^dQ�,�+�(��F=��çR\?v�"�#3���;r�)�Z%,�S�XȰ*�)��ѥx���,����uQ�v�R�b�$�z�!�lX��}���luL�	�
�
��6RhJl&�~��Qu�5,����餈f�[�g^nPI��1�)ʄ�rA�J�[xN�D#�蚭�ukfҴD�M�B����AD��"��_��Eh׀��h��եV1��5�.5��_�������f���%{
C��"�K���z3F�/�b�W�^�{��?�Ĩ� �y�(�
���PJ4�|+�Ϡ�t����W�/�$�?uցv��p�@�����J&sx��`6�j>Ц���3��V�1l�Q��ܬR��V�L�$�e�����Z��`��F�=u��£)l�I�.YK�mL��n��G�r����9�0ݡ��6��r�'* �.�-��RcV�m���U�,|\e�Q[JWZt�^|p�ͩYhO)���R��J1�㑆/\�Ê��iF��I9��*Ɯ�G׀�}�t3@�?w�:m�X�:-���K�e#��\��*�S#	��$�h��0���-�7�>`j�8>*���I��@� �H׶[F鉱��W��t�ɸ�����<�A4S�y��SK�+k2+�cT��WphtLt:��Ci1�r@�@��؛y������<?�\
w�^��"MnXc�TM�s�S;��7�W�v+���p��(���I��T 8x����s���_f��'�J�^.C}��-k<q�-�j�H��QT��9�x~�*fi⩻7��U��|}9��w����6#��:�������Z�L���C7|)4�ЙC3��;M����z��(.2�\4J��'}!��ָ�n�9���r�Nص5V��K���{<j7���snm+L@�h����d��J`B:�F�+��&P�v1���I8���d{?�|6����Q ���r'�p�	�Ӷ��(�퇜�K�C^���H�A���g��U��P+�q�s9����<�q{�:�d!��z�Bn3
1'5�/����N��P+횄J-Fq����\,U����h,pq
7��[������W��{��S>nE9Ȗ���Q>?McI���Ӹ �"WUy:�:�~�8���X�pu�8�`�z�����R�j]����G��J1p�:$�?�3�$�Zʒ*�>d�j�cP;U��PJ�}8�����H�vK�v�d*Li��@~N���$��-�վ4����m�jD�ڴ!fO�;�߆\e�J��U&S4��5��l~辶u���Z�*���d�s�_�2
���c�q��?�,<���j����ව�Lv֕|���Y�(�U*��l� ��UB��za��^V�2���uT?|j���KB_ּ��ՀE�4is�s��l܈����2�V:���=n�ڀ^Z˹=ˍW�����+��Ȉ(�^A-�@Â��z���^���=K�
��~���Nx.�����!;�7�xV�ִ��?.�`�9�����v��Ij��<ܺA�ʷ%h�X�)|G+���=�\0�p��A�8�f7N�1�h�y?�R�+�Ը[���6�X�.�]��C�c�u�(W�>��l���/�!)4��L�,u���Z����!�b�GR���T+��T����/ dφM52�ҥ�^�-	_צ[fo���i��E�f��x�]��d���~�|��7ܵ��S�aW~�fV\>h�dG��p/�)��;�I�s<�
oI�Y$�F�xF�s��!�{���w�bN5/a�(�� ]�D��$LaQo�+�i�� �Kq�s���_�¥y�d�⡌�V{-�q�-��MS\,6�մ-%O��|����7� Iy����,����#B��.�/Y�~P�1���}��xg.fx���P40QW��،49��A?\0wq�s����XF(n5ʺ!6q��j_?�/7[��^��_c>���+�n�SlLJ���g���aS��ИQl޴�W�)�%��v�J#�;�b#�F�R���ፊ~���P�*ӣ4��m����о��u��lln��?~��}��O��9�����q�0Z	=e��V�q/˚ͽ����ҹ!�987���p��:ůSK�@�b���/����3��Z�V��zZ��&Z�0=�}��E��٢��b��l����OO@��C��H�LI���<��l�4G;Uwˤn���� 2ct����g�	��OQR�J.21|�Pai�4���cjUJ�BÖ�s�}�DLRV�).��n�3��-3�(��
�Z�e7��s�q�����S����0u��?��I~���y�����J\���_��,�ʄ�Q*�r�x�C��Z[|��h���ȿ���o,�f:�f��-_%���xQ�LK�8���q�;�>S4�J���7|L�еoY�������{j�>�"�"R��k�U��a:�Z4�����F���+���P�}���~y묎<+�̶�w��=x��4�&W��Z��ւ1����8v��s������(£0��J [�S��ވ@K�a���$U����@���:8
��lI󴐎�r���Ka��� Q�I����)�����[l�m~��/,��\L �	}�Z���J{���x9�vC�2
��Q�9SdGd&|�Md�=�T���as��9���Pn��ވ��.�,d��a�C�l��zN�ދ{����y������*yO�<)��}�p���'[_�����l�?�'��_�dz!�9�aW-1���ʟٿ���X�f�Ȃ; 6�&ܰ��<^��:z{v��l N-��g��z��$��n�3�"���tl���Z����:��v'�[vJ��>V�c;f�����L�k��b�u��A�ol�Mm(� &0����'�����[x�1k�8cϞ�9 k3N`��HZ>���t�Pc�����������7Z#��c��a��>Kk"Hg~����y���������ãW���@eo^�z�[k�V��88�t��
|a�-���=}b !S����Az�E�,�Ű�̽$%���x�E������bO�r��}5��'�����������O�xy���t �|eݽܵ�qo:�^���H���#k���N�η���S|���j=�Ma�	�b���{�u#L_��J&���%[�:-}�h|�k���<x�:@����w;��?����
�S��cb�1����0כB�P
d-4�/p�c�^0��n��G�d!�fA��6�[�/d��V�i�9 � $�-|(����z�҂�@�(�	�����^� б����m���{�+H]��pQ`sO�6���%���*�0f���>'P�м���r~[P�r6�n��O/��n�� &4Лx����}۝��s�v2�s��o�E6.�} ɱ���3\ӻ�_����ῗl��c����;s9�{�̈��`�4�E��q�����-΁����OАcG.,� � #�yQV�l?��U�s:��8��ȞĄHfs�!7h�$�����AA;Gl{�F�{�V8و�.y�0a�6,�Sr>�}ut����i ��@�9��/��0��=��!�*Wj��j/��X����)68>ez���~��)�8x���9p����*�Q�a��1)zB��� 8�|�d����*��Aq�g���M�nn0�8�~�~���Z�㯏��m�Q{�>H�B��ڀ�-^4���-���_���9��&[+��҃ւw�U֝��6p���������*�%����x�C�<���=���7�Z�q�+�����!e��)��ݶ��|v����'f��Kt�E�)��Qh���D~C�!�y�$�0N����������2��H�����_R��p�q&#xՎRf���|��B^���4D0f�v��e<�.�ޅ���_`�}	�G��8��'E���`G� �3��^+�qF�b��z��~e�o��o�M�u�;p67�8�[���]ڝth�A0��F�>��d+���s	偊�^0��k�ކ�q^��x ���Y�[�G��qDV����4^��ߞ��4�:�N�D� �B�Cm�+��W�&BO��р@h��py��遤�]���E�^���	�&����M#.��0 ���y5"����t��m�z�g��,���p�!��=�M���%�	a�����0��`�(A�E�1p�9��u|���wI��s��r��7��I�cm��Y�����4V�����7���6�Lm�^�9�ġl�DpM$䊆����9� .�I��,J ]|���X�`�����M9?ZyI��J�]9i ?��o���>,C�FH�T��V:��m�����&�Л�JmG\�ȮI���@l��88z{��MB�j�R�(3~s���kK ,�X+�F�s`+~�k�Cd�;����6
c\��9g�AU�JHe�WW�t]ua]�1�0\Ybq���5�O���3��n����=�|�����q���$O���"g�)���*|����N9��7�;��SÓ��0�����~�!?�]N�����~��$���L����X����{�ߧ�6��e�o,_�x��[���1=@��9�ᯜۘ���'�.����6�X�1���˃��u��t��m/�ʗ�g�����I�a25��#�q�H=5���-�H?�ǅ?ji�#X�h��P����;L?�M��?���^�/�>yh�8'�e[������k�(	���>F>�I|�Ap$3o����'>�G��1�_(1i��8���O�dr�� ���;��%���J�;�y��0��G�l�XRI���}URoXSpm��_ǽ[�������%���J�4�p^ua��p�yl�X9�t� 6]�<l�.ˍ@_��M���/��_��	��.�1��(!�(�a�s�*&�� g�$X�d�;��16�|b.<��@��r�J��L���+fԕ���븲�ʴ(�>��⒘Tc
��� �+s�Z���<͎b�)m�*�tK�,�_��ܨ���:L�)�F��a��po;�� 0�)@�k�k�ŪZk�v�����~NV��SJ���,M�kh2�-K�yu\t��?���s��?���s��?���<߰ �  