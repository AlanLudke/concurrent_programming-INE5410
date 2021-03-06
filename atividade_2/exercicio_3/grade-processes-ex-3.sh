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
�      �X[S�H�Y��Dh�M��(0L0Yj���ZL\��6]�jG�JȾ�/�ڇ�ڪ<�O���ݒ,��2S��N�{�-�����s� ���sY^�j� ֚M�]]kV��	��F���\]��*�Z�R_���Si�(��@\�����w��a��s7�*Y���_o6t����ݏ<'d�{$s��Z���j��� ��7���/>+_0�|A�K㗓��קݽ����U5��O^�nV�>���\
�k{z� `}8K��M�A�7 �����`yd�+8$�ʊ0�1+�\r0����F�r�����'����`�92
��ù��Й��(��n@�2����̐7�u(�	��G�qo�W���_[���
d��������CU��Ԍ���n30���N'X.8x,�Ŗ�}F�;�?�����h}JX|��;����O���N���*w:�N���4�������)q�n"����栝թ����m����|/�J+Lx}�U?�t�|ң�{��Ǔq_���M��f����)�����]Q����Q�/���nZu��{pt�j�j{���O;/��i5�>`{x�&��ps)I�G��^�r�`jp\�$�d\JG`I�x9
��K��R����+uZ��Q����"j�8�A0�rM]ِ�(\��O��!aDC���RILsu��OF�)��U:�@�x���R�zBJ�&YWK�+�O�?*fϷ`�r������>0����ͯi�?��c��=�_�����jC��� [�ƫ���v��ͩ� �,S�5Ð��0�33C�J؟Y�a]�`��P.��_�G���l���.�su��66�7�u�*J�.�cA�§A�]��|>�\,��l��s�p.�1.7��H��m��B�P(�'$���j��{�i>v�}������^\\���&�P%�2v�`���򒒞��"�ޘ��>#ߓ�>ܕ"B�\A��*��b12���������P
HIfn�Oh�Iܖ��	U��]���i��jq��
��r���;b�m��������ֶ�[hl��Yc��5�V��6KU�*�#��1<B�~��C6MT��3�Ɏ���V�� �ښ1W:&Q#/k�!��3�b�H-�?W�4D:�6%K���U�=���O#�ya:��Z�c�����,�*5���Gs�T��>�'���ÇX�IK=�TU��0��*�ߒ@��Z`)(wJ�J�<X*���k��؟br�_��HHK��#˸��_ų��o4�k��
��������S�+���<-�=Q�pă�p�|���-�>R�A�^S_��W��>�q	/DN�3����}6��B���4qD&����9�¾=�'i�<��'{��+�x�_X��8�����u(xe&e�/���%��G�s削4!';������E#o��#����@}�9�w�rӘ"��-0c�F�%-�R�A!��q)�c#�8��dx+�	x���F�\�H;#X/�)oIg�����B�x9i��Q�/���X�8>9�3�M��w�"%��Rr���9<W���X���PkN�T�zV�s��]����Z�a�΄�5�t.Ċ����mfa�=wޘ;��n^ �|,�֠5I�K��=��jxcm<ުbl�63�e�:y�Y��{l7>Vř,�#U0T�I�YB94�x�'&���{3"���0��V =~ã�ҭy�G�2�(�)�7��)�g�9;'�ƴ�h���L�u�}V�<�D�p!@�J]Q�\�K(8��.s�:��/3K6���
Xr�Ü�����Ȝ:,@)�O4�~ߍ��B�0Q��r�N)n�؂�wC:��8���WQ�Èa��#.��DΑçS6���
��о�B��/|Z�MȻ�� 7��z
?9ZG7���r)�u�+�Z�(~R��
�B�����y!��u�8��o=6�� ����豏T�?��������S��s{o�������*+�bL��(�$�YXA���[,�������Gd���F(����X���������J�9��o�� ΃$Քܶ�:`����^�y8Q�ފ�3���q���{I�d8�s����D�W�'���+����<|�cU�QfgN���*�z8���}��;����/sC/��Ւ��$���jO����x�:g8���[�6F�{�k P  