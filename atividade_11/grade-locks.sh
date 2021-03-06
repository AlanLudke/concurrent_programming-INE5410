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
�      ��VG�����Xk�03�+l ��8 '9���Ѵ`bif<���ٳ9��_�۪�J#�$���'�f���^��L%�~p������U����V[��o<���zk��Xi>����j���8���� �!o������� ��8C��_o�F������q�_{����,Ǿ#q�ٿYk�����P���Wn�G�s�6ΙY��x�h������oo�k�ݽ��F�4p<XC��u0��5�S(��;���:���5 ���f#�M�� �r��R�P���K�ӽ�v�Y���6:���1�<ҵ�('DH)���f���������]
W��U��)��13��������㿾R_��}�l��>x��;<��O9�^�	Z��7�t�����c!�|'�O��q[�[o�l��+�O1������o>�-U��O4Q6��Z�[����z9��:ċgñED`\(�o��Y��7�O�D\���G�Dp�����:�>���1�k��
�Ƽ�_]��Z�zc��1����C�����lS�??|}��(7�Co����F�Y�m�w�m?�Qn��}@��g����W�����d)�c�P8�
�r�BYP�W�_��L0�sLo�i���:��"��8r|�˿��kĝ0X��c����Y>�#p����N�B!�B��dcy.�Ir+�c�;�ᇨU8�eU- �Z�S�F"{�	����V 5Y�,����&i�8���6���������1�++�E���������N�w��#*����{�T��0�S2E�t�W��S�.�Џ�0�e�/�#�~:���9뿝�)Í���k�]�5(W%�=�G�ċ��p�ĝ�������N�W�0o��cn�_)��\�@ê)�v j>!س������FY��0�h�KL6���֣G�ʵ5E�S���m 5��5|��̤l[� �4�F�D��xz������ 0kH�O˪�>�U*1�IN߬�-��c@Z����p�-��ZU�d�i3�d�"S�M�䍈�1(���6]e�?�/I�JyK�]h	6P�0bs]����OB5���9`4����x�zȺ���l)����]N��  67'������Z�$/�T19R����R�&�S"S|I�9��]#ya��z����E���2J7JEF�R�C�湿H���+����3� �H �*����\�Ie5� �Z�z O|��W��q��f.Q|�e2�����������!:�W��)��Y]���������4��!�z8��:�+���S���?��B�9��@��[/��}��O)"r��:�m'`t6��M�jBk�o{��o�)�ta?�<̅�	1���x��'��"��#�1�~�/!���?d�����yϺb��"d�fC<1�O:��ޫ6&:)Ѕ�g�x��y9�R��-���v.�`n"ǥ	��u`S�D���1$)ʕca���q�m,5�KϹ�aO�݀���}�St4�ێ*���YK�W2�4�v,oO��1���eL��	�[��3��.ݔ�sz9�;	g6���[_݊�%��qh��+1/z�����ULH�O�<=C�0<BoR�J���s*=����J�:�B,��f�FC	&vш%����z�o����anR�fv'�a^��S*�.�j�m3�c]ѹ�D3,�0����4UI.K'�R����ҩ)�螎�s��4J����yV�?�>s�(~ � �"��׬�M'$���)89�H�[�>?��,)S���O-�F^���H�#�#^��^���8m����X�e���x�P��g#u�������!Ʒ)���M�Ҹ��2[w��'����lxϰp�k��۩~k;��nfK�KG��E�To,�Y�Wyf���-��s'��R����2k��?�s�z�vj�ΰ��</��s|^�HU#�\�����de���:�n,B�\-�&�w����l���ݕ��<jz+��f��nqA+����F}���/���!-D|�>p�6��'w�h�6��#*YT��)ވ�~ۮ9ԢH������`�FV����9oJL^�W[W�#U��5gx�̄E��.������#�(P#�������	ja��"5��z����~�<*-���/������2^y��������YC3IC�����weM2�>�Û5��|D_T<eթ��;�vM�.���}ERQ6��X)p�����1�<�����_�I��}~r��<p"e/�K�˗�_2ޅ����C����wv��iR��FV���|9��D`C뜣�Hq�wࣇA�OJ���i"O8M@z�d��脉"G̗�6-�e��ܴ���S�%E��U������Jc;W�G���دWZ�6�e��M����H>��Q@���<N� w��v����cD0�I��Y����^��
�v7&���(]$��.�7f:k�O��L�e��@5�v���[����bZ��0�����|u�jp<���P�+dǂC?{ۻY|@����?�!�ұ�_�1�9�?��Օ���V����w#���7Kھ�S,�o��{}�&z3�=�>��kF�߅��kI�����V�ĖR��1����`cteG�=��k�֐1|�t�n�:u$�MG#�(����>�$L�l!���vg��])��P��>ٟ t)��1є���`x��$�71u�<����}:�G�{��]��fF��C.hvn%&(Z��I�w|�@�����G���G,.Q	�	�!���:D-�qKE}�-x��,E}ǎ)�'	��@PJI(D�J ˆ҇א��^Ū^�Z�
�Ϥ��&N�^��B�9�h�S��X>�n�퟈�������Q{G<�O��70�/x`���x�j��ľA�Z�7�L#���0v���h�m��iL�����Љ��1�eO���h`�=��K��=
�h,\��V2�v)2��R˔�ly�/���E=�jߜU���kƞ�$ä<酢Ʒ#!ǻ�~��q��(��PĆG⿵\����!k<�H2��,CY�)���M(GT!�BZ��P��]RU��DX4�[��T�*����<5.r=OI^)�z�5}O���\TA⠖È����M�q�;�_���6@�U�M���o��w���������J�
��
�^�k1@Eӣ�x&����5]���u���x6W��k	�܂��t�p�g�P��f`�\����k4��m��$�;'M���9^�t���2*w��_ ���@˝��NS;�^B���N�˶e�2�+"O˔�(�c1c1c1c1c1c1c1c1c��Nf� P  