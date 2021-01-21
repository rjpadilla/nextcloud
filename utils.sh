#!/bin/bash

get_manifest_sha() {
  local repo=$1
  local arch=$2
  local var=$3
  docker pull -q $1 &>/dev/null
  docker manifest inspect $1 > "$arch".txt
  sha=""
  i=0
  while [ "$sha" == "" ] && read -r line; do
    architecture=$(jq .manifests[$i].platform.architecture "$arch".txt |sed -e 's/^"//' -e 's/"$//')
    if [ ! -z "$var" ] ;then
      variant=$(jq .manifests[$i].platform.variant "$arch".txt |sed -e 's/^"//' -e 's/"$//')
      if [ "$architecture" = "$arch" ] && [ "$variant" = "$var" ] ;then
        sha=$(jq .manifests[$i].digest "$arch".txt  |sed -e 's/^"//' -e 's/"$//')
        echo ${sha}
      fi
    elif [ "$architecture" = "$arch" ] ;then
      sha=$(jq .manifests[$i].digest "$arch".txt  |sed -e 's/^"//' -e 's/"$//')
      echo ${sha}
    fi
    i=$i+1
  done < "$arch".txt
}

get_sha() {
  repo=$1
  docker pull $1 &>/dev/null
  sha=$(docker image inspect $1 | jq --raw-output '.[0].RootFS.Layers|.[]')   # [0] means first element of list,[]means all the elments of lists
  echo $sha
}

is_base() {
  local base_sha    # alpine
  local image_sha   # new image
  local base_repo=$1
  local image_repo=$2

  base_sha=$(get_sha $base_repo)
  image_sha=$(get_sha $image_repo)

  for i in $base_sha; do
    local found="false"
    for j in $image_sha; do
      if [[ $i = $j ]]; then
        found="true"
        break
      fi
    done
    if [ $found == "false" ]; then
      echo "false"
      return 0
    fi
  done
  echo "true"
}

image_version() {
  local version
  repo=$1    # nginx repo
  version=$(docker run -it $1 /bin/sh -c "nginx -v" |awk '{print$3}')
  echo $version
}

compare() {
  result_arm=$(is_base $1 $2)
  result_arm64=$(is_base $3 $4)
  result_amd64=$(is_base $5 $6)
  if [ $result_arm == "false" ] || [ $result_amd64 == "false" ] || [ $result_arm64 == "false" ];
  then
    echo "true"
  else
    echo "false"
  fi
}

create_manifest() {
  local repo=$1
  local tag=$2
  local x86=$3
  local rpi=$4
  local arm64=$5
  docker manifest create $repo:$tag $x86 $rpi $arm64
  docker manifest annotate $repo:$tag $x86 --arch amd64
  docker manifest annotate $repo:$tag $rpi --arch arm
  docker manifest annotate $repo:$tag $arm64 --arch arm64
}

create_manifests() {
  local repo=$1
  local tag1=$2
  local tag2=$3
  local x86=$4
  local rpi=$5
  local arm64=$6
  create_manifest $repo $tag1 $x86 $rpi $arm64
  create_manifest $repo $tag2 $x86 $rpi $arm64
}

build_image(){
  local repo=$1  # this is the base repo, for example treehouses/alpine
  local arch=$2  #arm arm64 amd64
  local tag_repo=$3  # this is the tag repo, for example treehouses/node
  if [ $# -le 1 ]; then
    echo "missing parameters."
    exit 1
  fi
  sha=$(get_manifest_sha $@)
  echo $sha
  base_image="$repo@$sha"
  echo $base_image
  if [ -n "$sha" ]; then
    tag=$tag_repo-tags:$arch
    sed "s|{{base_image}}|$base_image|g" Dockerfile.template > Dockerfile.$arch
    docker build -t $tag -f Dockerfile.$arch .
  fi
}

pull_image(){
  local repo=$1  # this is the base repo, for example treehouses/alpine
  local arch=$2  #arm arm64 amd64
  local tag_repo=$3  # this is the tag repo, for example treehouses/node
  local version=$4
  if [ $# -le 1 ]; then
    echo "missing parameters."
    exit 1
  fi
  sha=$(get_manifest_sha $repo $arch $version)
  echo $sha
  base_image="$repo@$sha"
  echo $base_image
  tag1=$tag_repo:$arch
  tag2=$tag_repo-tags:$arch
  docker pull $base_image
  docker tag $base_image $tag1
  docker tag $base_image $tag2
  echo $tag1
}

deploy_image(){
  local repo=$1
  local arch=$2  #arm arm64 amd64
  tag_arch=$repo-tags:$arch
  tag_time=$(date +%Y%m%d%H%M)
  tag_arch_time=$repo-tags:$arch-$tag_time
  echo $tag_arch_time
  docker push $repo:$arch
  docker push $tag_arch
  docker tag $tag_arch $tag_arch_time
  docker push $tag_arch_time
}
