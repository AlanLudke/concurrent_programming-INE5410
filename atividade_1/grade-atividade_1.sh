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
�      �<�V�ȲyEG��dl��K�fv�8��I� �v�cKI!>f��<O��c��/RKn�@Yg�$uW׭���o�h�P�{��໥
���|V�V*�S�����r�VY]�>�Tk������XJ�8����΀~r�|�Y��OS�������}�~��w���8�r�u#��nI�Y��\�g�u����Tn����o���K'��t�g���[����N��1_-<��?�lT}? }w@������q���3R��
9n��zPF���s����u"b̫$K��D�g>1wv[+���1y�O\'�2�ȑ띒���!CTNuZ�P�z�G�Bʾ�px�V���⇤��K4f��������$����������r�GP+��G�-�������hvaX��_���S��U��.�ۚ�"Q\��#�����ut�3旎��GG5��nf���"�2��`��@�n�<���:|/�8���Hp�����gZ}���8=Z>w���h̲���l���R����]$��_�4����vgm{��ngc��_�������V��lk�����vR�`�����/�,���%o<� ��@��<�)#�p@��3��9
I>��c@�'�>���3ЊU�������D���Dh8����|2tܐ��d䏻���"FZ^��IȒay&�qr%�%���C�*�(%eGU5��B��S���&IT��|r#R�QN�%��2*����?�,ipJ���c3�&�Y�_]�����$��/���-{�M�E ����Z��"��g�1����þr��u֏���8b���O����Gӧ�w�t?LäpS����M��u2_�\�>"��G@�� �ٜg�#?`�Cr�/9�A�����x>rJ�2DM�"bZ��=k��ٵ���i ^��:gc���osss��uD���w��r�TI���g�顷�Z�#q���Ɓ�,���d$"� �¼iJ؅�eI"�,�_?.��b�� 2�(�	�,���e	eY�4m*�Q��]
�9���ۗ[8�m�{�������	-X�U�1�RP�I���|
����AV@w� ���p�1�]Òs\�8�
� dssB\��F�V�@%>Iw���#%\>~�%Y���$'��G@�r΁<k�e�^�'Gƣ�Z��(F�Ұ���iz4�F������!��|���`�1G����V��0�a�O�]�O�����b���t��e�͔��Ǉ�qJ������9���ų[������r��_[^͎�+����i��{=�'���[��Vgo��:�Z��/헶]��b�7�0�z��<�/a�s��ųM%�ń|W�����v=7�+
�{�Ew=�Q�軽4xJ���J����B�����f���h�> L7d��9�! a�!�Z�^������	L=��Za�Ν�{fcg�P����x�UndfЃ"�	$Sꃈ9(��Ʒ;���O�>dr[�v:��3�;/vIM�츼0r{&��D�E�̀��.e_b�$�+��(�C�.��r0J#;�M�5S�*B�ڡ3�d��L���8�PP���3>����س�g��oٻe�rT�D�O�iB3����	B\���F�FŔfъ�����g�ƙN��#�t�O���p�Y�_��A��T��/ť��������VhL��+ku���r?��EJݮ���,5J��0�l^o����hxt�c�A:o�P;�7t��L͋p	�N*��F��#<�I���<^�l0��W"�vq�HA�\o�w? n��b��a�����lt�Z��ݝL���5�â$T"K�j���eض��+��D�7��rR{�}�[{�$��Qt��]�)G��$�MSC�Ły��}�n��#����j�%�c�MÒW��U!�Q�{"��R�� ��sv�I
�9Cz�&��M��e:�� �L}��ad�H�1�?�^:@�,H19�!����#�A�� x41T�ZfJEB.�,�*� =ˆ���J�����K�D�X2&3c쬄y�¾�
q�n�p�Y&�@K�!8��ؓ����
`A��ơv�\�T�`S�����z���:�ub�EY���Ƒ�(�e��8�F~��k���3�]�~@)�2��X�,W,C��{���й�+��5&�R���oHЇ��&J;'�'D�B�WR!��\�f��U�;.N���!5�IXW�c,�tj9�L�#Ǌ�0(�ȇ����bV	+Č%��8��m��+�1�Z�k�\��|:I�SAs��CR�����#�g�>%b�����U�*Յjb���`U�E"�p:��*/����� σf�4<J4�����P�1Q�( X#*�f�����L��:��P"1�y��U�_۩I��>�r���a��{x�Z��d�I� ԮS��XV�_aH7��V�Y'jH2:oà�՜jg�4��$�<����إxM*���B��z�sV���ZT�_�Rfd0L�Y�d���Ӻ�=��9��Q(����,�M����+=Jrf�q�����HZ�f]���S!��͆�W{�{��ݝ�&����`aj%��|��n���(d���`�t�.\�� P�Ƨ�&d,Fmh�	cqX��_J��;�M���`;B�>��:E�Zy��Ұ�jJi>�4�^R���AT�
���t��ɹ.OҺT+k�����#M��� ,MJ���ٜ��g��f��5�O�fa<FI�b���1�#Oow�^n����N#���<Ǖ�V�= ��t)�7`�-V;�lu�`Ն�";����i`L���x��|�(dzu=��� ��C�7%��$�g�d�r"G�:e�?]K��*�l���U�P�|E�vZ����t��T�C?�|2��B=gpS�)<�@y����
�o��]Zd��a(b�p&��s���ط�P���Ѡ8�����K\�����bo��c�B�'���g۸킒~�aC�,��,� \=۬�\����ܠ~3Ȏ���/�W�,�K�V[��12Z�UKdm��_+�O��G��D�מ��c�R�G��>�����b� �ŧ�
>�����d�=}q��*{,�G�A��=e��ڥfG	����8w�ɔ��Y��$J��?d+L�*1B'�� �r�(���V�x,`�8O�% v���i.˃�/L�YX ~��C�XP��%����we� 
�G���� ��$�f�?Q���\�ND�evPd]k�.�_�1�f ʞP(�Q �Ȟ`!Vy�����1�a'�F{�߰�y��L��Y5:�'��#j�F�|k���I7p��`Ep��F!L��
�⤎4�П��t���Y�|l�4��.P@��-�{�X�c�tv%�N��Xժ�+�_�d��(���j��l�Ĥ��=6��*�0qԥ�[o!�?*e6�U!P#�XlLib�=�[�SQ��z�.H.�*.�3SB&�>�����<@M���X�?{�O���lx����_��Չ�������w�t��m¼�_)�B�v���=�l�0Ac���R��
;m��9��tv�Wd�#>D�}T<2�Ԧ�`$�N�}N��5_ơ�,�!���������s�4�Ё��,;���`��9c'7�Ä���vm�Jl�W�2zh����C��(b?�1lf�!�.dbMa_�\��ȯ5����U�O�HTq#�W���B6��l�OW�#�"9]��@w�_j(( ���XjW0X�N���d��guRv��d�2�ש�ɀm3f��udV}j��i�}G�)ݑo���5��e:��;62(d�"��������t�Z�iN�] �����m�Oq5��eE-Wsd���,[-��m'fi��NC���m��������И�U�+��_}�>���4G�4���!>	�0�Cx�5���㊨9t�}9������0�ui~�O�9�O^9]��luZ۝V��;Xߘ7���G�$&�(�u��ڻ�,Y��;�gt0 c�>^���B!1��8dC����߈jΐe����)1�����5���t��E*��H
�s�/#?�/8�e/P'yG���qRZ��M¨K��qK���U*��G٘w-���W��v�b�� M�G�	?�U-2p�4��Y�?�N��}y�*�i��Np�z:f���=���k�f����m�9h���^�vk�?!�뽃�w��}��f��Q�T�T��'+Βa@�&���M���i�����3��k�����ܟ���������om5s��j9;mMr���1P�f3!Bv�+}P��Oðpmn�鋒()]�Qr�7KU��)�e�^Gř.P�55�k�N+K"0Ύ��;�eyh��1��z�(�a��m��Y&_q^*:�iqI.@/q����$�Q<�>�h�yK���t�<ڤ{"鉅�\L��8��ޛJN�ʧ^K<tk� =KH�ߙ8 �<$;�PA8ᐓ �81�[z,���JR)N!�,���Ė��Tz�5�>�x�֞�C@T؄�
�R�qW@�z�~*M4����"���DCEE����1��5k*�vBz��W��H�G�wŮ�����s�k����\��M�����w�t���PF�ޠ��nv=Lwl򲙼&>s;a����q=���WŴ�u��!����-�Bᘯ�%�x�Hva��hw��G�����]쉣m���������0��%�V��T@���7�p<p������ZT���d��"*D#.����/U�Q�J�ϴ9�B$5nP�9�a�5r�yJ�#����N��\�!�����\H����BF��i�Wj���M����Mف��Gk����t��Im��Y>�%�� �k!�h�C3�L��XCR���ׯ�-�T%c�����$�,�. �h�k�:x	�J��YJ,�g~U��
�{���c�ﴛv{����^���mቲ��XJ��'�)��Bv��\7J�� �Uo��n���9��A֟.��{�H�0�+2����xao����\�?r�Ł�kK~�{x����BB��\�Q�TזON <"��ս8��#��M �NX�O971�쀰�)Y2�K�'���G}�T%�r($�3x����W�]����X�����eJ� L v���g�iH�4�Ƴb�2U[���)ڐ�!���	�:0�9ol�h��⎮v"ru�n�='�������?�kA��l�U�]m���k��,���*���dQ8C��J7o"��r�<���V�dРJ"�ML�3R�-~0sB�A�+�!���t�LÐ�y%�$3:yc1S��l�ȽE���^�1D�Ø���#��:���]�6��ߐ��_��2�<�6��M(y�E��ut+M�{�3Ÿ%;�r\��O��Y�N��2y��
QK&wH�s�Su�n"��4���]�� �
է�*W���
ȿ���Cez��F(-+��!0�er��^�M��\X����>M����t�:�H���'�H�Ψ1�c��:ޫλ���{�|���nY�h�Ђ�QH�P"
"�W�����@�H��5��`�D<	�f빭�F+�'xRM���c� �Q7į�C+�D?	���wv�q�������~�7�j Q����������v�u����W�)P1���(^@�h���/��ü[������!�O�� ��M���?|�r���א>R9��#R�F9�8���
+WU�S�iE���7[��-��5������!W��D{��)L��*s#�U�^�!F�>�GF��Q����]���l��nҴ��hV�����7���&aL��'#m<�:��EuK:��f��n�0�i���CЏu�
��F�$�����7���a0[��<�E��-�d]��a���5&�������b��r��0������U�]��HbK<��������q�H~��
hb)Cy��U�%�֒s��-�%oj��NqHHb<�I����c�ikSu�R��Ǯ�� ߣWns�*[�Fw��h4$�65V-a�r�`��SˏAX�M�\5��m������^�m�<l�ʋ��G�	�&��{�ُrτ���YOx�<8�y,Y��j��ZM��-YeT���
|���{�+����`7`_8�p�_�ݢ�(5�,�]`�8�T( +�m��:�m��:^��M^��=r�x X� `� <�]���^���y���l�BYK̝�O�2�bZ�1�qDˋ�v�Z�Оh��l2_�2U�D�Tj|����|�4�e��^�h��B6tNy�N��I����&��i��0[�ϟe�C�D�*ӡ�A�QZ|��Wj).ǁWM$m��)RE1�H�A������K�,s��I�/��V�c�cL1�����'3;t1����:��>+f!b7�B맲��.�]�׆�ͼ�/�El�0�4/L��WB�tb��h/	���e�P�A��Yb��� �q+��̐���n��R������iEl6�w1��f-�MxA�&)��M5�x��v��r�nM�e�D�r-����?~(
����fTH�P�S���j~*0�a�DK�P4,�H͉D�˓}�h�R�v��J�f\]\i[�&�%�B���j��9��x1tŧqK����.s��&�vq��
�Z!����]�C��~��-`%�A�����
�ŗ䏥�4�h���)�_�6�d��.��Z3����&V�A偤�T5)�
՚p~�be�zQ䈯�ź�|���NwS�̷i�3�1U�U'�i�5�v�`���l��s-ӊ���-1�N��v�7�w�s����bmM�i��'`Z
Ѧ^S2������K,:�E�rp���gj�E%&�b<ҟ�n��m�}>ARN���>��1�r<.U���͢�X�ՠ�8ru�%Ҳ�r}�C]��>��h��<��y�&�h�}cM ���H0
JB?n�o���]g�Ix��m�<�$���t�Kͺ��V�E�F�V A�])��"}� ����
�~��y�KU$+	�7�Y�w7ŵ�fqO��X�t�ܻ�B�3� �(l�6���Zb�Z�,�I$g�.5fk����-�Y����ƛvﻠ�J��Y���%7Bsᣳ��6y��e���9W�,M\�↼u�j(Vl�3nMW�٘'K�T��㾴*@h��5)d6:=L{�F�5�9�&d�l�5y��s�Bq�i�4.e�Z�۹��j��"]�st]}�\�++,�M��8�ӥ����$(�.�}���1���QU���Y���	hO�xit0�l��1０M�3��'1(�^�=����� ��R���Tz/d���YC�mj��KN�5�����H�@��R&��I:�����~�s9����"�j{_ۛ~.�O[K=߯3 r��5�/k���)N�P+횜	�����O��C#u�ε������(���\��]���Q&
��ɛ�~k�A:�5V��!3+H�on"�����ӭՑ�=�	L��������ā
k���
�ݖ�f�|"w�u�Ll�%���ho�~� '�R���KZ��:j��^G�D��j�:���^�خ�L��l)�Ϩ�F����x�/��}���Q?>u�Lw�nf/�nh�/:�f>6"v@�pE���`�
;���H,_�Y��֫.8#fb���!G�l�,t��vãzE��/S��n���8X��g���	�/=�@xs�Y��mK�bࢹ�%� m��&�),7�gG�2pH��8t*9�׀ATI����i�ؗ��,�T����S�ͺ_r��A�U��v_? g�����=�ﬗ�1p󶊢k��Ӄ�،W<Zـ^F͙���;qy��+��Ȉ(�VA;\C���y���|�����0�*��d�U��(79!�YCv(=�ڄ�i�k��<�z��΁}�4F��|����M�T��Aˏ�6 �V��������B!o҈�s�,Ū�ǽ4��n��d��f�LK9/��R{=_�&�,_`���ֆ���u�a
h��L¾��*��-'��4�R��"z���Ux��ZP]�䌰�Z�j&	�����bsK���3�H T�1�TeKҧ���A֜j�8`�΢00�7D��W}0���8E�����P��Ss<�(э�y���!
J�����������G�!8�])X��:�B���tNN��Q���9��m���4NB@W�
�>�	,�Mb�{���z*��u.w��@.��$��u8b[o5� ��Q�ǋ|Vi���!��O�(�`��s(��ls����VcXaMv$�Z07����Xe�[N�P\��u]l��PU���^nۺ�Q�l���r��Wb�W�"��%�|qM�׊_qś��h���S��*��X�h�����JLm�R߫V�
��D�K�2^TF����/�����i�i���������|�p��.R���@k��y[~����=�Fa��b1_g����,:��?��)��#ӝU:��O-ݏ�8߬�q��/ůLe0Nx峬&Y�ni4����:̗ɝ��.;���^$78q�d���P�2"1�ƽ�#�G6�L�	��Yu�H�=tF 3�@7ۘL��<���鬗��D�y��̮�n�mLk��V5�*�T�l�k*�!ae���:QЬr�/���Zt�
�F�e�f�cxqo���T=��� u�?~�87�?Y[��w�*����;<��U�=�º�ʜ��KB����3�Ǳ):C��4ά�0���[�9��Y�`)���gͪ���3��9D��S��~o[�8�@��){���crR����-��/�JdsG?����6h�˖~깳_�n�ek�G��&M�!�rk�R��$�J{�|�Ǟ
 )�_ֲk"�� �#{���؇׺�(kjr9|����+x�_��Ǯq�o���04E�8�M\�^�S'�^�@K�b<�PI���w��qg�@]�e�A��YZ(/M5zi�%�dFG� Q�U�{	���3����m��o7��%�q���7A��>o��v��s��#�^n����<��^wS�aE�ԫHs=x (��{�f�5g�AHnC��3{#���b!�4�r�eC��c�����T�C�a�7�F���3��7�w���E"?������ɹF�3�?q�<��\4��t��h���`���.���O�y�_��-�w��ŞoǧW��1�c����4�/t+���!w�{��a!�t��	��?S�4�Qd�Ռ�<aOmǋʔ1�^2j@h��<S*"���7�[��*z�8>�?�|4;����ߢ����U,Y�#ӅUFJ@ɔX�JH����&����2�4�g�E{��x<�N;�}�L)hd!O���vdU9c����:N�|Z2���n��$� �G��ve���@��h�D��^� 3T.kV}gI��4�
 ��֍@;�K�Q_�!zQCV����a)Ćl�ym6���%���I�O\�y��RUl��=zfCeHþ6�*��U��_	 ,m6�Fm���vu��oЛ�X\�l|2�D2�|bd��;d��q��5���Ot�f�� �ЪK#����a��� 0��|��v1<O��6����x��i�Sc:�:����%�4-e8�{�ޠAqP�`�ja]57���	�1TK� �6RW��B���vN����[�0�����W�����2=�	޺��V�{��<B{�{t��{tGC�
@�����f�(>zD{^�d��V�ZP)Gc�NB�E[��7y�Β����{E��)�"{^>����ަ����"?��4������|�zr�6P�>t���<I�>�NkD�?z�~)g����f���DF�ǏK���s����ᣅ��.�WK��7��败B�3�=5�E+�W��_�9�Ϝ�l�2�ʸ	B/��z>�
Q�����}�%O�`]�l�����X��{���6�C��`Z���A*~�&�[5J���";�=�n9S�����j�����o�Ǧ6d	"��C�q�h{��g-�JK��:���=a��C�L�O�d����[u���9T�Ӏݘ��N{��+6[k{��)���*)� z>f�V�І��}�4��	��%a�M���^|`��ǎ��Xm�������1�������t�m(R��p��JRRAG�cG��ʼ)DE��AQ�XcG�`�g�X���0#i�'5a�T� V�$�
+ ��%F�s��>�.�Wp�����s�ޅ�
$����ʾ��b������u�8���fp.�~DHf�8��f>�X�9�T��J����
�s,U��Z�HTeY��*J�K,k,��V� 2��|�*+�,�dN,U��z����P1PG �>$���:R��>�I��dJ��Y�M��v��>�8��'��#���K��q����(/����ɔN�|<E#�ͷQ{�c������7��.R�э�Oh~���C�v_n7�r�gs�������i�=#�>�+�9��6�ϥ�C�rR�_���%�Cw�5����l��Y�[>?B��1��g���_�/j��a�Q�}�.iS�;�TT�q;�a�����;r�	bf�i���k��hI:��r�`��2�� ,�>�
�`|��
|=�}�b_��ae�r�ï�B`�m��en�i�nW(��U�ф2 a8��i��fO{����ܚ����荺�oD����2k:�V���7�{�Rj�ԺcV]����H�19�L�����Qm�n%��Z-�|5���������;I�_����`�'����	������	��:�;�V�{��%�9�Z�D�ʲ�qdc�ş����!^d����X��m���+���ij�z�W�8�Ykw���7{[h�؋Ш���?i��xx�}������>�l/bv�y��; צ�&䂉*�f8��W����%�	�5�g�SK +���>�a%|̡Q� ����2:���#���]dv�A�cn���Vy�{��@Ǻx����ڽ��>P���-b�t�-�n��q�u�+2��^0�d��ކ��e�j[��4������m�9�	�'<��}��{fO���Y�$�&�O�>ᡍƼ�䭤��C���^�ޅ��¿0Sycwp��
��v�f�c��6�4&Y�g�P��������w�@E0��l��@�У��=�iX��b7S;syD�d��r���/�BaPE���}��Ŏ��&)�FTw���I���qJ��v����E��G�j������<؀�L�8����-Ԣ��~ �˾������x������7T*��٘t�Iے��([0\�h��;�{~��;�a�k�_�	Y��N@kg�?>��{����G�s�E�0��� 31wb�pI��8XNl�ٰ�'��Ly�8D@���	��vЉ�qGk��`����-8p;h��a�G!
P�ɩA���_��{�!l��L�Q�,$��V��<�V�� �����n�QU��]]2� V�<֎ڞހ�;i���3���lD%����F�8O�<�-��,����~��Q�[�=K�诪���U�q�q�"{ڑ@!��������bֳ��`��BQa��]��������=�>�Z
���Qv(dd'�bʳI����%�� ��q������7��f�V����d��  "\�pbG]߳hv�+�e`����*[���'��7e8���|g	����KN_ð���|
�f��;ӳ�}�?��%�"�إ�����Jx�!�zv���-f���K�$�[Q�-2(sP0∕��^ 3�Q ��t����H��t(&G*��A�-���d2��� �!��7�HU����F.���aƜF�I'_]&.!�����7��Q�I�=L�rN	u�/���A��[�0f�(�~�(ŀ_Y�{�E�{
��z���r�ׁ�[��s�6�zt�u�?�H�&�g:�3���T��(�׾�U���=���er���h��H��;q�z�Yf����qʔ�P�|et��?��nА35�A %���+ϟ�l�MhlE-��{��	��1J\��(���F�Ht�<f0(�6�NyP2@}�/�=G��ZY�ϲ�N�0
`�>�q�u��z���d��V�,�ۄ�r��4LipǠ:١R�i�1>w=� ��w{�_�?�H�����U���\Cyy)�W
<22uP�����7?��w� ?"%�8�PO�0F�n2hj���$����Ȏ8��4���?z!�H��H��H��H��H��H��H��H��H��H��H��H��H��H��o��e6  