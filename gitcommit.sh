#!/bin/bash

# 1. Ask for the commit message
echo "Enter your commit description:"
read commit_message

if [ -z "$commit_message" ]; then
    echo "❌ Error: Commit message cannot be empty."
    exit 1
fi

# 2. Add and Commit
git add .
git commit -m "$commit_message"

# 3. Pull first to prevent the 'rejected' error
# --rebase keeps your history clean by putting your new commit on top of the remote ones
echo "Checking for remote changes..."
if git pull --rebase; then
    # 4. Push only if the pull worked
    echo "Pushing to remote..."
    if git push; then
        echo "✅ Successfully synced and pushed!"
    else
        echo "❌ Push failed. Check your credentials or internet connection."
        exit 1
    fi
else
    echo "❌ Pull failed. You might have merge conflicts to fix manually."
    exit 1
fi
