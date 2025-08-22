#!/bin/bash
set -e

# ----------------------------------------
#  Purpose: Identify which feature branches contain a given tag's commit
#           Then create release branch, merge features, and raise PR to st
# ----------------------------------------

TAG_PATTERN="release-2025-08"
RELEASE_BRANCH="release"

echo "Starting tag analysis for pattern: '$TAG_PATTERN'"
echo ""

git fetch origin --tags --prune
git fetch origin --prune

# Step 1: Get tags
TAG_NAMES=($(git ls-remote --tags origin | awk '{print $2}' | sed 's@refs/tags/@@' | tr -d '\r'))

declare -A TAG_TO_BRANCHES

# Step 2: Loop through tags
for TAG_NAME in "${TAG_NAMES[@]}"; do
    if [[ "$TAG_NAME" == *"$TAG_PATTERN"* ]]; then
        COMMIT=$(git rev-parse "$TAG_NAME^{commit}")
        BRANCHES=$(git branch -r --contains "$COMMIT" || true)
        FEATURE_BRANCHES=$(echo "$BRANCHES" | sed 's/^ *//' | grep '^origin/feature/' || true)

        if [[ -n "$FEATURE_BRANCHES" ]]; then
            TAG_TO_BRANCHES["$TAG_NAME"]="$FEATURE_BRANCHES"
        fi
    fi
done

echo "========================================"
echo "Feature branches per matched tag"
echo "========================================"

if [[ ${#TAG_TO_BRANCHES[@]} -eq 0 ]]; then
    echo "No matching tags or branches found for pattern: '$TAG_PATTERN'"
    exit 0
fi

for tag in $(printf "%s\n" "${!TAG_TO_BRANCHES[@]}" | sort); do
    echo "Tag: $tag"
    echo "${TAG_TO_BRANCHES[$tag]}"
    echo "----------------------------------------"
done

# --------------------------------------------------
# Step 3: Create release branch from origin/st
# --------------------------------------------------
echo "Creating new release branch from origin/st..."
git checkout origin/st -b "$RELEASE_BRANCH"

# --------------------------------------------------
# Step 4: Merge all feature branches into release
# --------------------------------------------------
echo "Merging feature branches into $RELEASE_BRANCH..."
for tag in "${!TAG_TO_BRANCHES[@]}"; do
    for branch in ${TAG_TO_BRANCHES[$tag]}; do
        CLEAN_BRANCH=${branch#origin/}
        echo "Merging $CLEAN_BRANCH..."
        git fetch origin "$CLEAN_BRANCH"
        git merge --no-ff "origin/$CLEAN_BRANCH" -m "Merge feature branch $CLEAN_BRANCH for tag $tag" || {
            echo "⚠️ Merge conflict in $CLEAN_BRANCH. Resolve manually and commit."
            exit 1
        }
    done
done

# Push release branch to remote
echo "Pushing $RELEASE_BRANCH branch to origin..."
git push origin "$RELEASE_BRANCH" --force

# --------------------------------------------------
# Step 5: Create PR from release -> st
# --------------------------------------------------
echo "Creating PR from $RELEASE_BRANCH to st..."
gh pr create --base st --head "$RELEASE_BRANCH" \
    --title "Release: Merge features for $TAG_PATTERN" \
    --body "This PR merges all feature branches containing tag pattern '$TAG_PATTERN' into staging."

echo "✅ Done. Release branch and PR created."