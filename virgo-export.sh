#! /usr/bin/env bash
#
# virgo-export: Get an expurgated copy of the Virgo repo with no history.

#==============================================================================
# Functions
#==============================================================================

function Show() { # [--|-n] text_to_show
  local ECHO_OPT=''
  local CHECKING=''
  until [ "$CHECKING" = 'done' ] ; do
    case "$1" in
      --|'') CHECKING='done'; shift ;;
      -*)    ECHO_OPT+=" $1"; shift ;;
      *)     CHECKING='done' ;;
    esac
  done
  [ $# -gt 0 ] && echo $ECHO_OPT "$*"
}

function Warn() { # [--|-n] message
  Show "$@" 1>&2
}

function Error() { # [--|-n] message
  Warn "$@" && exit 1
}

function Announce() { # [--|-s] text_to_show
  local NEWLINE="$NL"
  local SHOW_OPT=''
  local CHECKING=''
  until [ "$CHECKING" = 'done' ] ; do
    case "$1" in
      --|'') CHECKING='done'; shift ;;
      -s)    NEWLINE='';      shift ;;
      -*)    SHOW_OPT+=" $1"; shift ;;
      *)     CHECKING='done' ;;
    esac
  done
  [ $# -gt 0 ] && Show "$SHOW_OPT" "${NEWLINE}*** $* ***${NEWLINE}"
}

#==============================================================================
# Constants
#==============================================================================

readonly NL='
'

#==============================================================================
# Variables
#==============================================================================

RM_DIR=false
VERIFY=false
GIT_PUSH=true
GIT_REGEN=true
GIT_COMMIT=true
GIT_ACCT='uvalib'
GIT_REPO='virgo'
DST_DIR="${GIT_REPO}-export"

#==============================================================================
# Command line arguments
#==============================================================================

declare -i SHIFT
while [ $# -gt 0 ] ; do
  SHIFT=1
  case "$1" in
    -c|--clean)      RM_DIR=true ;;
    -v|--verify)     VERIFY=true ;;
    -n|--dry*run)    GIT_PUSH=false ;;
    -nr|--no-regen)  GIT_REGEN=false ;;
    -nc|--no-commit) GIT_COMMIT=false ;;
    -ga|--auth)      GIT_AUTH="$2"; SHIFT=2 ;;
    -gu|--user)      GIT_USER="$2"; SHIFT=2 ;;
    -gp|--pass)      GIT_PASS="$2"; SHIFT=2 ;;
    -d|--dst)        DST_DIR="$2";  SHIFT=2 ;;
    *)               Error "'$1': unknown option" ;;
  esac
  shift $SHIFT
done

[ "$RM_DIR"     = 'false' ] && RM_DIR=''
[ "$VERIFY"     = 'false' ] && VERIFY=''
[ "$GIT_PUSH"   = 'false' ] && GIT_PUSH=''
[ "$GIT_REGEN"  = 'false' ] && GIT_REGEN=''
[ "$GIT_COMMIT" = 'false' ] && GIT_COMMIT=''

#==============================================================================
# Check preconditions
#==============================================================================

if [ -z "$GIT_AUTH" -a ! -z "$GIT_USER" ] ; then
  GIT_AUTH="$GIT_USER"
  [ -z "$GIT_PASS" ] || GIT_AUTH+=":$GIT_PASS"
fi

case "$GIT_AUTH" in
  '') Error 'Need GIT_USER and GIT_PASS environment variables.' ;;
  *@) ;; # Auth string is ready as-is.
  *)  GIT_AUTH="${GIT_AUTH}@" ;;
esac

SRC_REPO="https://${GIT_AUTH}github.com/$GIT_ACCT/$GIT_REPO.git"
DST_REPO="https://github.com/$GIT_USER/$GIT_REPO"

#==============================================================================
# Get source repository
#==============================================================================

Announce -- "Get '$SRC_REPO'"
( [ -z "$RM_DIR" ] || rm -rf "$DST_DIR" ) &&
mkdir "$DST_DIR" &&
cd "$DST_DIR" &&
git init . &&
git remote add -t master source "$SRC_REPO" &&
git fetch --depth=1 --no-tags --prune source master ||
exit $?

#==============================================================================
# Get last commit from history
#==============================================================================

Announce -- 'Get last commit from history'
COMMIT=`git rev-list --reflog --all | head -1`
[ `echo "$COMMIT" | wc -c` -eq 41 ] || Error "'$COMMIT': invalid commit"
git cherry-pick "$COMMIT" || exit $?

#==============================================================================
# Remove/edit files
#==============================================================================

Announce -- 'Remove files'
FILE_DELETES='db/*.sqlite3 spec/* test/* features/*'
Show "$FILE_DELETES"
rm -rf $FILE_DELETES || exit $?

#==============================================================================
# Individual file edits
#==============================================================================

Announce -- 'Individual file edits'
declare -A FILE_EDITS=(
  ['config/admins.yml']='s/^(\s+)[^:]+:(\s+).*$/\1xxx:\2xxx/'
  ['config/database.yml']='s/^(\s*)(host|database|username|password)(:\s*)(.*)$/\1\2\3xxx/'
)
for FILE in ${!FILE_EDITS[@]}; do
  Show "$FILE"
  sed --in-place -r -e "${FILE_EDITS[$FILE]}" "$FILE" || exit $?
done

#==============================================================================
# Bulk file edits
#==============================================================================

Announce -- 'Bulk file edits'

declare -a DIRS_TO_PRUNE=(
  .git
  .idea
  app/assets/images
  app/assets/unused
  db
  lib/config
  lib/doc
  public/assets
  public/images
  public/uv-2.0.2
  vendor
)
PRUNE=''
for D in ${DIRS_TO_PRUNE[*]}; do
  PRUNE+="( -path './$D' -prune ) -o "
done

EDITS=''
read -r -d '' EDITS <<-'EOF'
s/[a-z][a-z0-9_-]*@virginia\.edu/xxx@virginia.edu/ig
s/(https?:\/\/)([^.\n]+\.)*virginia\.edu:[0-9]+/\1xxx.virginia.edu:xxx/ig
s/(https?:\/\/)([^.\n]+\.)*virginia\.edu/\1xxx.virginia.edu/ig
s/([.\/])virginia\.edu(:[x0-9]+)?(\/[^'"\/\n]+)*(\/*\s*)(['"]|$)/\1virginia.edu\/xxx\4\5/ig
s/(_API_KEY|_PUBLIC_KEY|_PRIVATE_KEY|_USERNAME|_PASSWORD|secret_token)(\s*=\s*)(['"])[^\n]+\3/\1\2\3xxx\3/
EOF

find . $PRUNE -type f -print | xargs sed --in-place -r -e "$EDITS" || exit $?

#==============================================================================
# Create a fresh repository
#==============================================================================

if [ "$GIT_REGEN" ] ; then
  Announce -- 'Regenerate git repository'
  chmod -R +w .git &&
  rm -rf .git &&
  git init . ||
  exit $?
fi

#==============================================================================
# Commit
#==============================================================================

if [ "$GIT_COMMIT" ] ; then
  Announce -- 'Commit changes'
  git add . &&
  git commit -m 'Clean copy' &&
  git gc --aggressive ||
  exit $?
fi

#==============================================================================
# Verify
#==============================================================================

if [ "$VERIFY" ] ; then

  REV_LIST=`git rev-list --all`

  function Verify() { # text_to_show egrep_pattern
    Announce "Verify $1:"
    git grep -I -E "$2" $REV_LIST | cat
  }

  Verify emails              '@virginia\.edu'
  Verify paths               'https?://[^\n]*virginia\.edu'
  Verify keys                '(_API_KEY|_PUBLIC_KEY|_PRIVATE_KEY|_USERNAME|_PASSWORD|secret_token)\s*='
  Verify config/admins.yml   '^\s*([a-z]{3}|[a-z]{2,3}[0-9][a-z]{1,2}):\s*([A-Z][^\s]*\s[A-Z][^\s]*|xxx)'
  Verify config/database.yml '^\s*(host|database|username|password):'

fi

#==============================================================================
# Push to github
#==============================================================================

if [ "$GIT_PUSH" ] ; then
  Announce -- 'Push to github'
  git remote add origin "$DST_REPO" &&
  git push -u origin master
fi

#==============================================================================
# END
#==============================================================================

exit # Nothing past this point is executed.

#==============================================================================
# OLD VARIATION: Commit and rewrite
#
# This was a failed experiment attempting to delete modified files from the
# original commit.
#==============================================================================

Announce -- 'Commit'
export CHANGED=`git status -s | sed 's/^...//'`
git add . &&
git commit -m 'Clean copy' &&
git branch --remotes --delete source/master ||
exit $?

Announce -- 'Rewrite history'
FILTER='echo "$CHANGED" | xargs git rm -r -f --ignore-unmatch'
git filter-branch --tree-filter "$FILTER" --prune-empty -- --all &&
git reflog expire --expire-unreachable=all --all &&
git gc --prune=all --aggressive

#==============================================================================
# OLD VARIATION: Export
#
# This was a failed experiment attempting to use fast-export/fast-import.
#==============================================================================

EXPORT_FILE='../all'
IMPORT_DIR="${DST_DIR}2"
git fast-export --full-tree --all > $EXPORT_FILE &&
cd .. &&
rm -rf $IMPORT_DIR &&
git init $IMPORT_DIR &&
cd $IMPORT_DIR &&
git fast-import --active-branches=1 --depth=1 < $EXPORT_FILE ||
exit $?

COMMIT=`git rev-list --reflog --all | head -1`
[ `echo "$COMMIT" | wc -c` -eq 41 ] || Error "'$COMMIT': invalid commit"
git reset --hard "$COMMIT" || exit $?
