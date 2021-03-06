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
�����WsZVtcL.`�U�^�G�#�􏹰��+v"�x9%����:}�y��Rkè�V�,�K"�nU�L��۱�����|c��C�ꆺt�ƛ��#�~���ɣ�����d��8w�>c�<�ℝ�F��J�f*��r��ɢ���,����[���@���*6�X��SQ)0^�}�~���|_�=��-}��ZL��,T��H9�zŨ0ݰ��HQ:D!���1Ó��n=�u�hea��EM����� �qHį�#�[�I�<�������k�&�	�\�������1�����_���a�`��m��I7���UǱ}q4�f���i6զv��X��|�<7V���˿�2���_]��x�� G��}�r:vR�]gV���'cӊ ��o7���&�\�)��C�(e����S���U�]�]9��u��ŤO��g�������MqI~���#b�$ַ`в�\ �	ɾ��hfhkzz�==�����cq�����.3��]�@r�o:l����������"@=>4�6����5�㘋>b
oZ=ג��o�>7]����ϲ�x���-���\-����'�`��%�����q�TX$��8l�{��/�������£�Cr*��ڈ���=[��W�<����͞s�K�\QC<ߣ�3`
̅}[�
8��+�\���TY�n0��i��D=�&�I/e{~�t�ͫ��o������*x" Z�`Թ�(�?�0
���d:��$����C I7Vʑ�[�Ѣ{j�Z�jJ��JX�ܺ������z�'{ﳱ��z����VL]<��� �pd5�ٖi2��j/�c�-� �I�#�= �ht��V�z9p&	�&���Y�.�R��ڠ�2�3��UAl��:�}^�pYn�ܼ��6'σ�̓PuSܧT��\o��S��-� �O��L@3�H7C�)��}'�&3�g��E�^fKy�y��X�L��Σ3��c!�R\Σ�z_��$��w֖����N��A�����E��5�b�����{�1��-��p�( !\bw@B��S�N��Ԉ.ó��f^�ή�"�M���"Aի
�d�jy���^L�?�L��bz�N�	)46y?V۩�T�����$�f�[�g^nPQh����2a��ӠR��Q!��H� [�5��@�a&͖ȳiY(�ټ�D$i�O��q#���a��qyu�U�p��@�(N���r��,����]��p������7gT��-j߸����˰��9�������b(���0��@S�Vh��2���?g�+�_�����@�FC8h����9�m,fxa�`֣�r:�����s��2	+�6X�U�6�T?��+W8�t��;�b}�d�l���Se��=�2����[Zkbz��|{�Slpn�v�,Lwh+�E��ى
�sfKȷT�+[r>��4���l�fKJҢ����S6�z�=��hp1��B��lb.�#_���S=��1��YZ-��["���� ���-��c�ȣ��Nq�Z�ˍ�
uedgF�&i��(�G�!F+z[ o}&�pԄq|V�u ���=�Bɶ[F鉱��װ�tve�Gu�vh�(�)�<��g��+jR��v*E�+8�yT��<��Gi��2@�@��?�5��ʩyz����7��хJnXa�4M�ss��:��7�W�v+��}e\�"�m)g�/< 
�{sh�.6����	�s���P_�Y�O�8Bs�ڳ�er�{�/�߱�X�x��Ey3y�(9__�x����e�q׶��!ܟ��
�����J�L��e·m�2�o�e"����PM��#Q�')4
	��'}.��ָ�nE9���r`.��U����K\�z�=:o�����>&��2����:-��>ߑ�Dt��W��=J��7��A���6�)����4�f^P�F ��K����$�txNۊ�h���3lO��ּhA�H�@�Kɳ�\ت�Q�z\�TN�`�8Oa\F޷2���uo: �6 sR1�E����@�$O
�ܮN��|3.�����RU�t��?�\�`�kD��5����ϯ�G�(�&|܆r��\m�(�����$���Ӹ�����+u$�pq���k(��h�B���aLr[*����[	|���q��h���C
���C��C<N2��,i"�n�"��i�ІR�죉<�W\B ��)X��)�`�	C����o�q �Z�Ҿ0����m�*X�ٴ#fϦ;�߆\e�J�ҕ�)�O��q��^��m�+`Q+�=�O5��Z��ןΣ8���Uo��.�a'�����;���aB�Μ\Ɇkȝ�����ڤ��h�"k�
�6'/����fX�S����O-�~A(b��˚����&m�z.���;ј�~_�\�Fg��AC�77u�1_V˙=ˍ&.�Yg��;�FD!�
jI��������O�޼VX�۬ףl�c�˨&%h��$��`�:3�+�z�����;�9��|�qV������)��7����5&Ԩ|�	�k���h��B�����jW�4�����p���F����R^����j�ж�,]`���wk��}��3֕�\	�����Ͽ��d�)�e���BW�冀4�5Dΰ��#�b�Y+��T����/ dώM<�ԥ���-	_׺[f��C�24P�,Ʋ�s<ݮ�h<��W?z�^��w���Ôz��߲��e�G���㈝��e=��y�q�h���]�-�U,��ֹ7�R�?`��.ð:�;bN5?e�8��]�D���8R�����g� �Kq����ap	��e�m��2b��5oD�[�n릸�o!R��-#O�Q���s�7� Q�ڸW1-��'%3	�|fn�ф���KV��㝹T��):�wBQ�D]֋e`svP産��p���m��J�wc9���(��Xǥ��}� ��ly{�����J�W`��7gؘ��{�|uc�fT��1#߼k�o�S�Kv4e�.�F�wf�F�B�*_��;}����W��Q���v��9��$�x��/���l��G_?\������C�|O_�� c��S�����4�EY�������/�9���w3�`.�n�Q�Z8i��V첱�e��X�v�8Y����YSE�jbu����Z���[�\c� gnxz
o���<E�fJ������62i����Qņ�3Ȍ!�5�֞A�'tܢ>EI�+m8�t���C�ܮ=��mW����n�<��L��A��=��n��V:���r����a���&s�!�2Y<�?���nn����}��fV�o����K<�W���/n|�
^���	�#Wjd"
�:�9�%|F���f�qpq9�(�X
�t��[,%��Y[�f�%Y��_2�j�\v��]C㰮d�O�Hq�G�n}�}���T%�������B{����U�*u�6뻃�˄���u��٨�}Խ���7@�뗵���ke����>xۅצO#�kkr9|���n-�/K��Ǯu�s���0E�<J�C#�M��
�M�o��K�����cǠ���q���`K����8(W/-=Kfu8�&eW�J֮��J��X�����������Ť���7�GB�o��~��o���	F���ѻ!GG樛�(���f�ԃ|&z/#�́g�N0�9��<��"`��r3���,G�Y2��[��o�^�q�h~��qrW ��������zs��}�g�{jop3�K��ym��/����P�7L(�q4LS�S��%��t�%�S��i�����=� �O��L;����G���=����cc�E���R:N�$`�7h�6ϵEgj3���(=��F��l��c}�u�����!��H���94;K�Y0��	�L�M�Z���#T�7����N@�L��(:�F	;��ɴ�Z�1�Ir@
����o��2ژJ풞*���%���ou��|�|+
�V+��蒺�b��PB��~�9f������"#�%i��7�|�.}jl��Y�ؘ�v��W�J����O�}b./������D�1�V�$�H�����l�:(?߶Ӈ߸�ZN?�7�+�i|6ǡ}�f�+m���t����K�Џy��W�M��$���������m�1�N�ݤ�wp������7[-.@Q���SZR
&�~(�t�]�h�zC`x`U!2���V� �1��%�3�Q�n��9�����Y
��ٜ��Q�`\�1�,;�BP���c���ZS��i�m�@z%W9�^˜2��g��|Avg]y}�
x�$�O���w_y7]�;�2��]�*��ѿjY�68v;;l��!U��9������9�ͩ�<�"�����$��?��4J����������s���9?��=�z�oZ�St�ٕ�%5x%87�"�w�ȁBi����7v�ne%zR.S�9��e�g.��U:&�%��AĚc��ȶ���Z�T��T��F��߶��CX���)�?ſ"P,{�s���Z��D�f[�"��L<���1vP�[L@y��+�7�g ��_�<��8��^���, d.@�L��o��8�����Q�;aT�Y9F7m�fH�(�#A�f��&(6F��>���q��Ta�w��ή��ذO�BʯJ�FKb���Sɒ�["�s ��!����J
��n���k����۶�-��u���j�0�1�*d��ICK1�1����ҙO^3S�v�YnK�R��e TӔH]]-����
���'���a2��I���=��]&f���)�v��[̘dm$$k�CniFܛ����OwMWc�&��� @A��n�BSj�P�&_:n���*ΑS������ӛ��^�8�V�tY��/?�����aɱ�.{	
�p>�DjS@]R^�.V�Zs�cU�M�3>r�?�q:�Wsk\��W0X.�;}����_�+���T��o>|����>�?�X��ģM��Xղ���eͼn{����y-+n���ᴾ�]�V�Eu[����kd�rT*� Mf�C�ף�?�4Y�c:�� ����OV!���Lg��2��JI�� �O���AY��а�:��TE�
Hv�:z�bt�^�r�?��L���S�x:�L!����L���,U��/m��g~x!��"��ή?��da��S��0b�r3�{Ŭ 9WM5׆h����!ޔ����ύ}3_X�޻���6V7��%-��ۇ�Q�˥�Ϟ�������dʉ���8k���@�bz��:��*�a�����l£R�V��M+�>'M���M�Z��3PuiK��2K����:�O����L�Ɠ|DH%Ж��hNu���	���\˖�l��I\m�S�;m���ͽ�<�E�Cx���o��]gS �$��wմ���{�d��suz	��v��m4ɢ+
d��4[�&�T��xv�iTg
w�0���:�[N�!"��WŴ* �LW�lG|}��Wu���K�ǿ������������j��h#���������K<������H�yrz|tr���'Go^�?��������Cֹ`��~#8�?��J����S�ON_�n5���d�u���}�w`��x}��*剏�a��R�6��7��߼�~%�Ã���Q�O�>;x��d����=M�RM����g~��Y:�=�${A¼��4�E	�@��@�P
v��H��e���Y�w@J�~D���C�2pdh���5�F@�NA�&��I0�D����Ep} �/1�B�s���9h�>��'бmܟ\�6�s$|=���
=ʀ�W��	ji(n��C�c�	/������P���e/���V���tAXw�A `Bݱ?�M<���y�c��sG`n<��s�����=��c1{/^����΋O��c��;K�Ѱ���}=�S6��>��xLXdO��c�|@\������S���J�=44��![�` ���N���c;S�DdB�d��>������N䃂v���;�>���O���|O���Т;!����W{m��S��fk�7����'[0��7Mҳd��Լ����c��f��k�5��{ M���O����p@�l3�&�����ϭ��)�H��2L[DyF�8�39��G�iN`I���4�V�{�������ݘ�P��>���
��=�xz�^Bj,Ɣ�I4�Xi&�>����΄�4���j�y`����z�t4j	��c*V�� ��1�h��,�{�.-D�n�'B�C��/���-1��T؛x_��/1�C!1���N%�rADHC�Dv�@g@8���.�������9TE�h9�%yL'2���H+�m��҂,�p���&�1�����!�7���MP��{�+�_������Uz���?C�H F�<�6�3B��V�@����E�;�`�d:���pJoqZ�w"�>h�^8qcr�;�
L�tp	�a��Qp���mAӸ.�[܃EЉg,S����Ѱ(B׹w1��Z�߽�;�e
uF���<O����W���@&BO��M�	OZǱ���Nӽ�@�E�n�h8�	M��S��^9��۸�Ή���5�Q�����.aǲ�B��"��]�m4 �%	x  ����;@�� {F���#�A53�wC���:����w�˚�!�h���`*���~Fן�޹��p0�� �x�,�I4��ƽ8��_�yr���L!���t�06�S@WB85W�4�����i0 �)�G#�	�K	�+�p~�Oat�,��A #�0��ʖZD�-��3��M8 �7I�Ŝ�Ȯ����+  �~�t����ɖ^��QKR+s~Z��kK�,��*�D�������0�H��?!��<JP@qN��^��!�Mɪ���*z���~��(do���>�����M���&���͢����F?������b��%���z�	{�.�zi�,�#mT���$�������:�"Yp�]�&�Q�xU���]��˔�uQA�B�����?��mJr���3��e�Ti�� �	D~<B��Q�x@�_E��2���9����Qz��Q3y;\�Ěr \Aޖjm��?n�����p����vFʶ��ۨNY�q�ql�04��W�&�_����q��������G�wt���(�h�0��������%1���7b+����l���姐�S� bCE���d�3?US���h�5����y�,�ųx��Y<�g�,�ųx��Y<�g�,�ųx��Y<�g�,�����S��  