#!/bin/sh

function bail() {
  echo error: "$*"
  exit 1
}

function log() {
  echo ">>> $*"
}

function detail() {
  echo -e " \e[33m*\e[0m $*"
}

function show_help() {
    cat <<"EOF"
Usage: krh-prep.sh [OPTION]... EBUILD

  -h, --help	This help message
  --board=BOARD	Specify board, defaults to $BOARD

Convert a prepared ebuild work dir into a git repositor with a commit
per patch.
EOF
    exit 0
}

while true; do
  case "$1" in
    -h|--help)
      show_help
      ;;
    --board=*)
      BOARD=${1##--board=}
      shift
      ;;
    *)
      break
      ;;
  esac
done

test -z $1 && show_help
test -z "$BOARD" && bail "No board specified. Set BOARD or pass --board=BOARD"
test -f $1 || bail "ebuild $1 not found"
test -d "/build/$BOARD" || bail "build directory for board $BOARD does not exist"

abs_ebuild=$(readlink -f $1)
edir=$(dirname ${abs_ebuild})
ebuild=$(basename ${abs_ebuild})
egroup=$(basename $(dirname ${edir}))

PVR=${ebuild%%.ebuild}
P=${PVR%%-r*}
PN=${P%%-*}
V=${P##$PN-}

# revision: R=${PVR##$P-$V-}

WORKDIR=/build/$BOARD/tmp/portage/$egroup/$PVR/work
FILESDIR=$(dirname ${abs_ebuild})/files

test -d "$WORKDIR" || bail "work directory $WORKDIR does not exist"

# Stub out 'inherit' so we can source the ebuild
function inherit() {
  true
}
                   
source ${abs_ebuild}

test -d "$S" || bail "variable S must define ebuild workdir"

log Using ebuild $ebuild
detail board $BOARD
detail group $egroup
detail workdir $S
detail P=$P, PN=$PN, V=$V

# Remove 'http://uri ->' prefix if present, leaving just the
# right-hand side of '->'. Otherwise take the base name of the URI.
tar=$(basename ${SRC_URI##* -> })

plist="${PATCHES[@]}"

# Create list of patches in reverse order for rolling back.
rplist=""
for p in $plist; do
  rplist="$p $rplist"
done

cd $S

log Rolling back patches to original source
for p in $rplist; do
  detail Unapplying $(basename $p)
  patch --quiet -R -p1 < $p
done

log Creating git repo in $S

git init -q
git add .
git commit -qam "start"

log Reapplying and committing patches with git
for p in $plist; do
  detail Applying $(basename $p)
  patch --quiet -p1 < $p
  git commit -qam "$p"
done
