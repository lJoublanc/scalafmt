#!/bin/bash
set -e

version=$(sed -n -e 's/.*val stable = "\(.*\)"/\1/p' core/src/main/scala/org/scalafmt/Versions.scala)
tag="v${version}"
tarfile="cli/target/scalafmt.tar.gz"
current_branch=$(git rev-parse --abbrev-ref HEAD)

function assert-installed() {
  binary=$1
  command -v ${binary} >/dev/null 2>&1 || { echo >&2 "Missing dependency ${binary}, exiting."; exit 1; }
}

function assert-dependencies-are-installed() {
  assert-installed sbt
  assert-installed github-release
  assert-installed sbt
  assert-installed shasum
  assert-installed tar
}

function assert-preconditions() {
    if [ "$current_branch" != "master" ]; then
      echo "On branch $current_branch! You should be on master branch."
      exit 1
    fi
    assert-dependencies-are-installed
}

function confirm-release() {
    read -p "Release ${tag}? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        exit 1
    fi
}

function assemble-jar() {
    sbt assembly
}

function push-tag() {
    git tag -a ${tag}
    git push --tags
}

function maven-publish() {
    sbt publishSigned sonatypeRelease
}


function update-github-release() {
    rm -f ${tarfile}
    tar -cvzf ${tarfile} bin/scalafmt cli/target/scala-2.11/scalafmt.jar bin/configure

    echo "Creating github release..."
    github-release release \
        --user olafurpg \
        --repo scalafmt \
        --tag ${tag} \
        --name "New release." \
        --description "See changelog in user docs: http://scalafmt.org"

    echo "Uploading tar..."
    github-release upload \
        --user olafurpg \
        --repo scalafmt \
        --tag ${tag} \
        --name "scalafmt.tar.gz" \
        --file ${tarfile}
}

function update-homebrew-release() {
    # Update version
    brew_file="homebrew/scalafmt.rb"
    sed -i '' -e "s/\(version \"\).*\"/\1${version}\"/" ${brew_file}
    # Update url
    tar_url=$(sed -n -e "s/  url \"\(.*\)\"/\1/p" ${brew_file})
    curl -L -o target/sha.tar.gz ${tar_url}
    sed -i '' -e "s/\(download\/\)[^\\]*\(\/scalafmt.tar.gz\)/\1${tag}\2/" homebrew/scalafmt.rb
    # Update sha
    tar_sha256=$(shasum -a 256 ${tarfile} | cut -f1 -d" ")
    sed -i '' -e "s/\(sha256 \"\).*\"/\1${tar_sha256}\"/" ${brew_file}
    cd homebrew
    git add .
    git commit -m "Update to ${tag}"
    git push origin master
    cd ..
    git commit -am "Update homebrew submodule."
    git push origin master
}

assert-preconditions
confirm-release
assemble-jar
push-tag
maven-publish
update-github-release
update-homebrew-release
echo "Released ${tag}!"
#./update-gh-pages.sh
# TODO(olafur) update-intellij-plugin
