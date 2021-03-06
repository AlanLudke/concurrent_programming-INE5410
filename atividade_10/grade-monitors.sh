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
�      ��R�J2���F�&2A���H��P�`
������Jl�х��/[��O���힑dI6��:���.
K���MwO�Zs�3fuڽE��Z�~K�b�7�{�Ju�\[/���{�R��^��'�|���{��]���x���O���߳���C����_�U���H��'G+=��z�m-I�y�_-UR���Z-ރ�r������_��LK;��A������a����n��/�^���\�v�g���`�9 �ǐ�(���P��:xf� ��^d�#1M��H�8��"`݁���^�V-O��>:3u���ȱi�!�� 	$�NÓbX�m1�`C��{�\�{f����)pc�/����/���_���������7{��;�=���9��4M�\�]���]���S~}�+_��������}!���㝎|���d���\҃���:���)��i�R�p�a�05���D�f��I~���] �I�?�'����	�_3�'�����L�����x̋���t�W�aI���@<��w^P�h)��������8�m��j䫹���g���l�k9rP,�iç|�
�f�s��C^D��p�\�s�a�C�s�۱
ޢ<�Q �g�>�����BT���b�v���>gC���}o�;f�n6�t�c��ڪ�R�0SV���dI�<W�YH�P��x�
c��qSs�&�T~�l���̅�AIT9= ���7;���2bN�9��9��t�?~\���N ��W�/���7m^^&�˹���/��+��þ6]��u�G�~4�=~x���1q�ד�1f���7Q�I�؋��}������&�#~�0�z���3v�����1�9��'�A��|��<�g��U��,�\"ڳ櫝���F^�;�E�� �����u���|iCB��]F�A	coL7(ۖ
Hc�zj<�:���G|s�g����e9�}T*B&�"��8Yݘ'�X�s��yLCJ4̧+!V�?��H'�(%��r9gD�| ���m:�6����%x)�%%��T8��\�b%���X���	�J��DA��<B;��DD��7�BxƍGQA ��S�rÄb$y�N�tS��i"�B�*�S�SxH9�J��������1-��/j�בրs��
"J��SM�%��e#*=\b��=����!!N�#a��"�&(����#�k��<t��Z,jZ�aA��D�����&��3��cN������D��?�V���K%,������wcL#�b���=���yn�}J�:n�#���v��{�2=u�u��է�o&ȁ.TݲlO�=Pݳ-*I�q��̡��8��]���sg<��C&^Q����.�Н���o�.S۟�L]�	c�l��ݡ�0	�cc}��:&��^ϴ�!n!�w^71��~P$�őϰ�f�gC�����;�|��ϰ�p��B��x����&}���3�]6�E�e�)H����ό��粧�pU�p���]O�4�b��g2]��U��Z�(�i����^�i�S�B�T�P��-����$�Utw�-P)t=��RP�39�т5��F�r��1��@��mZ		�l��
��.��س�n!�3�S����?�n�	��pbO6��\�|^Ok�����<�)_��J�i��w5��9W�ս� 䙆1���0Y_��k�G7�Vgm�
1%��1��U��*��%ݢЗ�w>T�c�!2l\��޲����̐o�0	o�/�ɥb<�L�'��riZ�yH�58��T	(� ��.#�8v1�}�-�)voUw	!�����J!�#$��Uz;0d�m����%
�~�}��H�Tf�	���:���}K�YߧW���
r�c�> 11ƕ������00?��ѱ��x���g��>����7��9������;���>m��M���J�5��>V�>\�"��-�]8ėm���ێv�%��sݴ�&�w�MǲM�O_����g���o�Ђ��q*|z|�L.u�4��*7Ϩ͚1s���]��ߧ�qM����ۀ�9*>��F��Yu=��.W��8A7kݭ�-���s=놅��
�Vk�k�2z�o��ۙ��d����o�2��0y�{�M�WuK�1��[���S���J5{�{��vP�\w�X� p��F5����^�j�W�Z��I�%jQ�[����5��a�!D�c.z�׽���
z�=��O���`x����8u�"ֆ�^�f"�X���&QRE�4ۍ�Ӱ�'��~�?�."9R�I!��Z	z�ћ"L��xr���ҩ�_�c��U6c��=?1�X���!o���h��難g�ܓ߼�d�wl�<����O;���5.��T������V��G3sA���6���0���r� t��}��{��@h�|Y&>U)�e(Պ�Ӫƿ����v�}ب�U��@\����=�_������|��	���n���<���3�8���F�ʬ�@���hz�
�#�x@6��N��-L"��I?�[�x����~:8h?G�?���a߆�oz6`Q�6�� �N]�L�"Qǜ76ߩ�d3�!��E������Ǖ%mg�0&��'���ӑ��,6_�7M�|u[�D�0i"�s<f�4x\�Ï4��乜<]@ׄ|�.dU�/?�mU�9�C�SQ�l%�S��(o��iyW���w�Vf4�o��N~��h�����I�W��Ҙ
�Ds�]z��JŸGS�{��a���aTEe�-.r�v����ѓk�r_�z����Ej(���G��@-���۷��h��$�Db%�M��U�	T$���2� �2� �2� �2� �2� �2���� q�[� P  