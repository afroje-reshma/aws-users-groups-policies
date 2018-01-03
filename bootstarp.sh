#!/bin/bash

pushd `dirname $0` > /dev/null
base=$(pwd -P)
popd > /dev/null

[ -z "$1" ] && { echo "usage: $0 <network>" 2>&1; exit 1; }
net="$1"

profile=${2:-"default"}

function exists {
  aws --profile $profile cloudformation describe-stacks --stack-name $net-$1 >/dev/null 2>&1 && return 0 || return 1
}

function ctl {
  exists $1 || $base/ctl.sh -w $net $1 $profile
}

function stackwait {
  event="IN_PROGRESS"
  echo
  echo "Waiting for $1..."

  while [[ $event =~ IN_PROGRESS$ ]]; do
    sleep 5
    event=`aws --profile $profile cloudformation describe-stacks --stack-name $net-$1 --query Stacks[].StackStatus --output text 2>/dev/null`

    echo "  $1 : $event"
  done
  echo
  echo
}




ctl groups-policy $profile
stackwait groups-policy

ctl users $profile
stackwait users 
#ctl users 

#stackwait users
