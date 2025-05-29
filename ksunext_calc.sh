#!/bin/bash

REPO_URL="https://github.com/rifsxd/KernelSU-Next"
TAG_NAME="$1"

if [[ -z "$TAG_NAME" ]]; then
  echo "Please provide a tag name as an argument."
  exit 1
fi

# Store current kernel directory
KERNEL_DIR=$(pwd)

# Check if we're in the kernel top-level folder
if [[ ! -d "drivers" ]]; then
  echo "Error: Not in the kernel top-level folder (no 'drivers' directory found)."
  echo "Please run this script from inside your kernel directory (e.g., a25x-oss-sec)."
  exit 1
fi

if [[ ! -d "drivers/kernelsu" ]]; then
  echo "Warning: 'drivers/kernelsu' does not exist. No Makefile will be updated."
fi

# Use parent directory as workspace to avoid cluttering kernel folder
WORKSPACE_DIR=$(dirname "$KERNEL_DIR")
KERNELSU_DIR="$WORKSPACE_DIR/KernelSU-Next"

echo "Kernel directory: $KERNEL_DIR"
echo "Workspace directory: $WORKSPACE_DIR"
echo "KernelSU-Next will be cloned/updated at: $KERNELSU_DIR"

# Handle KernelSU-Next repository in workspace
if [[ ! -d "$KERNELSU_DIR" ]]; then
  echo "Cloning KernelSU-Next to workspace..."
  git clone "$REPO_URL" "$KERNELSU_DIR"
fi

echo "Fetching and resetting KernelSU-Next to: $TAG_NAME"
cd "$KERNELSU_DIR" || exit

# Fetch latest changes
git fetch --prune origin

# Checkout the requested ref in a way that always prefers the latest upstream
# commit for remote branches (avoids using a locally-diverged branch).
if git show-ref --verify --quiet "refs/remotes/origin/$TAG_NAME"; then
  echo "Checking out upstream branch: origin/$TAG_NAME"
  git checkout -B "$TAG_NAME" "origin/$TAG_NAME" || {
    echo "Error: Could not checkout origin/$TAG_NAME"
    exit 1
  }
  git reset --hard "origin/$TAG_NAME"
  # Explicitly fast-forward in case the local repo already existed.
  git pull --ff-only origin "$TAG_NAME" || {
    echo "Error: Could not fast-forward to origin/$TAG_NAME"
    exit 1
  }
elif git show-ref --verify --quiet "refs/tags/$TAG_NAME"; then
  echo "Checking out tag: $TAG_NAME"
  git checkout --detach "$TAG_NAME" || {
    echo "Error: Could not checkout tag $TAG_NAME"
    exit 1
  }
  git reset --hard "$TAG_NAME"
else
  # Fallback: try to interpret as a commit-ish.
  echo "Checking out ref: $TAG_NAME"
  git checkout --detach "$TAG_NAME" 2>/dev/null || {
    echo "Error: Could not checkout $TAG_NAME (not a remote branch or tag)"
    exit 1
  }
  git reset --hard "$TAG_NAME"
fi

# Fetch the complete history if the repository is shallow (matching Makefile logic)
if [ -f .git/shallow ]; then
  echo "Fetching complete history (unshallow)..."
  git fetch --unshallow
fi

# Calculate version following the exact Makefile logic
if [ -e .git ]; then
  KSU_GIT_VERSION=$(git rev-list --count HEAD)
  # ksu_version: major * 10000 + git version
  KSU_VERSION=$((30000 + KSU_GIT_VERSION + 60))
  echo "-- KernelSU-Next version: $KSU_VERSION"
  
  # Update kernel build flags: prefer Makefile, but fall back to Kbuild if the
  # expected numeric pattern isn't found in Makefile.
  MAKEFILE_PATH="$KERNEL_DIR/drivers/kernelsu/kernel/Makefile"
  KBUILD_PATH="$KERNEL_DIR/drivers/kernelsu/kernel/Kbuild"

  updated_version=false
  updated_fallback=false

  if [[ -f "$MAKEFILE_PATH" ]]; then
    # Check for ccflags-y pattern
    if grep -qE '^[[:space:]]*ccflags-y[[:space:]]*\+=[[:space:]]*-DKSU_VERSION=[0-9]+' "$MAKEFILE_PATH"; then
      echo "Updating ccflags-y in $MAKEFILE_PATH..."
      # Only replace the hardcoded numeric version (not $(KSU_VERSION)).
      sed -i -E "s/^([[:space:]]*ccflags-y[[:space:]]*\+=[[:space:]]*-DKSU_VERSION=)[0-9]+/\1$KSU_VERSION/" "$MAKEFILE_PATH"
      updated_version=true
    else
      echo "Note: No numeric -DKSU_VERSION pattern found in $MAKEFILE_PATH"
    fi
    
    # Check for KSU_VERSION_FALLBACK pattern
    if grep -qE '^[[:space:]]*KSU_VERSION_FALLBACK[[:space:]]*:=[[:space:]]*[0-9]+' "$MAKEFILE_PATH"; then
      echo "Updating KSU_VERSION_FALLBACK in $MAKEFILE_PATH..."
      sed -i -E "s/^([[:space:]]*KSU_VERSION_FALLBACK[[:space:]]*:=[[:space:]]*)[0-9]+/\1$KSU_VERSION/" "$MAKEFILE_PATH"
      updated_fallback=true
    fi
  else
    echo "Warning: $MAKEFILE_PATH not found"
  fi

  if [[ "$updated_version" != true ]]; then
    if [[ -f "$KBUILD_PATH" ]]; then
      if grep -qE '^[[:space:]]*ccflags-y[[:space:]]*\+=[[:space:]]*-DKSU_VERSION=[0-9]+' "$KBUILD_PATH"; then
        echo "Updating ccflags-y in $KBUILD_PATH..."
        sed -i -E "s/^([[:space:]]*ccflags-y[[:space:]]*\+=[[:space:]]*-DKSU_VERSION=)[0-9]+/\1$KSU_VERSION/" "$KBUILD_PATH"
        updated_version=true
      else
        echo "Warning: No numeric -DKSU_VERSION pattern found in $KBUILD_PATH"
      fi
    else
      echo "Warning: $KBUILD_PATH not found"
    fi
  fi
  
  if [[ "$updated_fallback" != true ]]; then
    if [[ -f "$KBUILD_PATH" ]]; then
      if grep -qE '^[[:space:]]*KSU_VERSION_FALLBACK[[:space:]]*:=[[:space:]]*[0-9]+' "$KBUILD_PATH"; then
        echo "Updating KSU_VERSION_FALLBACK in $KBUILD_PATH..."
        sed -i -E "s/^([[:space:]]*KSU_VERSION_FALLBACK[[:space:]]*:=[[:space:]]*)[0-9]+/\1$KSU_VERSION/" "$KBUILD_PATH"
        updated_fallback=true
      fi
    fi
  fi

  if [[ "$updated_version" == true ]] || [[ "$updated_fallback" == true ]]; then
    echo "-- KernelSU version updated to: $KSU_VERSION"
    [[ "$updated_version" == true ]] && echo "   - Updated ccflags-y pattern"
    [[ "$updated_fallback" == true ]] && echo "   - Updated KSU_VERSION_FALLBACK pattern"
  else
    echo "Warning: Could not update KernelSU version in Makefile or Kbuild"
  fi
else
  echo "KSU_GIT_VERSION not defined! It is better to make KernelSU-Next a git submodule!"
  KSU_VERSION=11998
fi

# Return to kernel directory
cd "$KERNEL_DIR" || exit

echo "KSU_VERSION=$KSU_VERSION"
