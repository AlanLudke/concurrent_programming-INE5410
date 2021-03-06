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
�      ��r�Hҿ�mY� �@��e�^�\�ؔ�T�05�OEH�$�T������O���I� ��8u�\Fbz��{�����-��w����v��?����~&�a�+U�V�m;Άe;����'��aD��ҏ,|o���)D��#�w�����r��������?dd��^7b��"u���b���_�Tj`���b�����Y�e^閄w�۫��������y}ϰ������{����3���8؅���>4�(`����]�k bF�G�r[�K"�����Iq��;���E�Z��6���-#A@L�#��H	�H��Ǜ3A���
V��(>P7��]*g�s�ib�G�����_���o����Ԭu�?���������B�>����uzX�i��B���B�)����th��Sh�{޸OH|�V�ys�.�[�{��Qj��V��tx�u2��]HJܩE$P�ޜ�U�r7��7��i�Ȟ3�喛��9�~��?H���V�cY�ooO�ժc���1@����1O�����!����7�{FY>t�//N���vR��zx�۞Q�x����I�|���ϐ��z�}���h"�lBlA3� B���3��B0�����{���<����=��O�U4�0���{�BĆ�Gρ�#��Ð��C��_,y�0WV���e�y��i�OD��o�U!�L��Z �c��|!�=ه����,[v9}��/�����dii0��*blI�;����*��P�_;�:<�w.�\� �2��h����O�)��4�2`_�0�ͺ�#�8�#1<�
���d���nI��"J�4��w��	ɀ�aI);>'3/�n�3�(�G~ �&4篴�n@��c�n(���#��5Eԋ ��{D��~zv�9�3r� ��Y��b�lmm���*8<�(������Q�����#�I鍩���hx"��ǂED����\�����&�"4ovڅ�eHp'=3 .c�P��b��`��꘶��R(uY�hZ0�Oŀ����|����q�C_Z�u�@���PaU��be��Y��*|��AF�pQ�v���j������W]N��c ��Ϩ+����U �$�t&M�i"�'R�
�T�dH�5��|@��!p?
�����Rt�-�9N_���R�x������t��GcG������		-S=ƔY��0I��ş����iXj-�T<�밟)?}۟���O\�#-�w+�����f��J�\Y�������A��\<�̴��+���c�ڀ����9��S�o�L(�|sH�QIK<a66����kސ�R:X�Wۂ#H��Ixy�O4�e�[�9a'*�\��b� ���G?�Z��~�A�u�߱�0������hr�Z]�v5�s�B�!�%�}�CV=����B�1���H�����9���V��)�^�)N\�L�G��5�.����!�T]��]��7>D
><���f�-L���ap,�V�X]Ʋ*���a2��8�5��W��u!�����jO]��Ye��bZ���']�26�l�6(Q����
#��7`�?������)?��2�)C���F����&L������7�	��v�\}�a�"=�2E4"��[��D�'Ȋb��9#���ڼ؋0��0�ro;��;�
�����`�qg�ے� ���;�e��LuH��uqe�R=�;B^3$��l����,�&d���	z�Ol0)j,� �O�U�0G��;_,�Zv�l4� ���~tyq�*��x`��r����d5=���#���!�>��W-
	����kU��� "㊻&�Q�MbXe���`zx$KM�"Ҋq�ɼ��,�Z�ms�9��?r�<���#K������؍祼��X��BŞӧ�FD���_"kX�~���ח (  