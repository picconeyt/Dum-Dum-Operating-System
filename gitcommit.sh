#!/bin/bash

echo "Enter your commit description:"
read commit_message

if [ -z "$commit_message" ]; then
    echo "Error: Commit message cannot be empty. Script aborted."
    exit 1
fi

git add .
git commit -m "$commit_message"
git push

echo "Successfully pushed to remote!"
