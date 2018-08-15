#! /usr/bin/env bash
#
# virgo-export: Get an expurgated copy of the Virgo repo with no history.

if [ -z "$GIT_AUTH" -a ! -z "$GIT_USER" ] ; then
  GIT_AUTH="$GIT_USER"
  [ -z "$GIT_PASS" ] || GIT_AUTH+=":$GIT_PASS"
fi
case "$GIT_AUTH" in
  '') ;; # No auth string
  *@) ;; # Auth string is ready as-is.
  *)  GIT_AUTH="${GIT_AUTH}@" ;;
esac
GIT_ACCT='uvalib'
GIT_REPO='virgo'
SRC_REPO="https://${GIT_AUTH}github.com/$GIT_ACCT/$GIT_REPO.git"
DST_DIR="${GIT_REPO}-export"

readonly NL='
'

#==============================================================================
# Functions
#==============================================================================

function Report() { # message
  [ "$1" = '--' ] && shift
  [ $# -gt 0 ] && echo "$*" 1>&2
}

function Error() { # message
  Report "$*" && exit 1
}

function Announce() { # [--] text_to_show
  declare NEWLINE="$NL"
  case "$1" in
    -s) NEWLINE=''; shift ;;
    --) shift ;;
  esac
  [ $# -gt 0 ] && echo "${NEWLINE}*** $* ***${NEWLINE}"
}

#==============================================================================
# Check preconditions
#==============================================================================

[ -z "$GIT_AUTH" ] && Error 'Need GIT_USER and GIT_PASS environment variables.'

#==============================================================================
# Get $SRC_REPO
#==============================================================================

Announce -- "Get '$SRC_REPO'"
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
FILES='db/*.sqlite3 spec/* test/* features/*'
rm -rf $FILES && echo "$FILES"

Announce -- 'Edit files...'

# Bulk file edits.

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
PRUNE_DIRS=''
for D in ${DIRS_TO_PRUNE[*]}; do
  PRUNE_DIRS+="( -path './$D' -prune ) -o "
done

EDITS=''
read -r -d '' EDITS <<-'EOF'
s/[a-z][a-z0-9_-]*@virginia\.edu/xxx@virginia.edu/g
s/\(https*:\/\/\)[^.]*\(\.[^.]*\)*\.virginia\.edu:\([0-9][0-9]*\)/\1xxx.virginia.edu:\3/g
s/\(https*:\/\/\)[^.]*\(\.[^.]*\)*\.virginia\.edu/\1xxx.virginia.edu/g
s/\.virginia\.edu\(:[0-9][0-9]*\)*\(\/[^\/'"][^\/'"]*\)\(\/[^\/'"][^\/'"]*\)*\(\/\)* *$/.virginia.edu\/xxx\4/g
s/\.virginia\.edu\(:[0-9][0-9]*\)*\(\/[^\/'"][^\/'"]*\)\(\/[^\/'"][^\/'"]*\)*\(\/\)*\(['"]\)/.virginia.edu\/xxx\4\5/g
/_\(USERNAME\|PASSWORD\)/s/\(= *\)\(["']\)[^"'][^"']*\(["']\)/\1\2xxx\3/
/_\(API\|PUBLIC\|PRIVATE\)_KEY/s/\(= *\)\(["']\)[^"'][^"']*\(["']\)/\1\2xxx\3/
/config\.secret_token/s/\(= *\)\(["']\)[^"'][^"']*\(["']\)/\1\2xxx\3/
EOF

FILES=`find . $PRUNE_DIRS -type f -print`
echo "$FILES" | xargs sed -e "$EDITS" --in-place || exit $?

function Show() { # text_to_show egrep_pattern
  Announce -s "$1"
  echo "$FILE" | xargs grep -E "$2"
}

Show '...emails' '@virginia\.edu'
Show '...paths'  'https*://.*virginia\.edu'
Show '...keys'   '_(API|PUBLIC|PRIVATE)_KEY|_USERNAME|_PASSWORD|secret_token'

# Individual file edits.

declare -A FILE_EDITS
FILE_EDITS[config/admins.yml]='s/^(\s+)[^:]+:(\s+).*/\1xxx:\2xxx/'
FILE_EDITS[config/database.yml]='/^\s*(host|database|username|password):/s/:(\s*).*/:\1xxx/'
for FILE in ${!FILE_EDITS[@]}; do
  Announce -s "$FILE"
  sed -r -e "${FILE_EDITS[$FILE]}" --in-place "$FILE"
done || exit $?

#==============================================================================
# Create a fresh repository
#==============================================================================

Announce -- 'Regenerate git repository'
rm -rf .git &&
git init . &&	
git add . &&
git commit -m 'Clean copy' ||
exit $?

#==============================================================================
# Commit and rewrite
#==============================================================================

if false; then

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

fi

#==============================================================================
# Export
#==============================================================================

if false; then

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

fi

#==============================================================================
# Verify
#==============================================================================

REV_LIST=`git rev-list --all`

function Verify() { # text_to_show egrep_pattern
  Announce "$1"
  git grep -I -E "$2" $REV_LIST | cat
}

Verify 'emails' '@virginia\.edu'
Verify 'paths'  'https?://.*virginia\.edu'
Verify 'keys'   '_(API|PUBLIC|PRIVATE)_KEY|_USERNAME|_PASSWORD|secret_token'
Verify 'config/admins.yml'   '^\s+([a-z]{3}|[a-z]{2,3}[0-9][a-z]{1,2}):\s+(xxx|[A-Z][a-z]+)'
Verify 'config/database.yml' '^\s*(host|database|username|password):'
