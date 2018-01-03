#!/bin/bash -e

pushd `dirname $0` > /dev/null
base=$(pwd -P)
popd > /dev/null

opts=wp:
w=true
ps=
while getopts $opts opt; do
  case $opt in
    w)   w=false ;;
    p) [ -n "$OPTARG" ] && ps="$OPTARG"   ;;
    ?|*) exit 2  ;;
  esac
done

shift $(($OPTIND-1))

[ -z "$1" ] && { echo "usage: $0 <network> <service>" 2>&1; exit 1; }
[ -z "$2" ] && { echo "usage: $0 <network> <service>" 2>&1; exit 1; }

net="$1"
stack="${2%.*}"
tpl=$base/$stack.json
stackname=$net-$stack

profile=${3:-"default"}

[ -f $tpl ] || { echo "$tpl not found" 2>&1; exit 1; }

##
# valid template?
tps=$(aws --profile $profile cloudformation validate-template --template-body file://$tpl) || exit

# create or update?
up=false
aws --profile $profile cloudformation describe-stacks --stack-name $stackname >/dev/null 2>&1 \
  && { action=update; up=true; } || action=create;
##

##
# params
function peering {
  peer=$(aws --profile $profile cloudformation describe-stacks \
    --stack-name $net-vpc \
    --query "Stacks[0].Outputs[?OutputKey==\`PeerCIDR\`].OutputValue[]" \
    --output text 2>/dev/null)
  [ -z "$peer" ] && echo false || echo true
}

function randstring {
  export LC_ALL=POSIX
  echo "$(< /dev/urandom tr -dc [:alpha:] | head -c1)$(< /dev/urandom tr -dc [:alnum:] | head -c15)" | tr [:upper:] [:lower:]
}

parameters=
capabilities=
echo $tps | grep -q CAPABILITY_IAM    && capabilities="--capabilities CAPABILITY_IAM"
echo $tps | grep -q CAPABILITY_NAMED_IAM && capabilities="--capabilities CAPABILITY_NAMED_IAM"

if $up; then
  for key in PrivateBlock NetBlock PeerCIDR PeerVPC PeerID AzNum HaNat DBUsername DBPassword; do
    echo $ps | grep -q $key || { echo $tps | grep -q $key && $up && ps="$ps ParameterKey=$key,UsePreviousValue=true"; }
  done
  tags=""
else
  tags="--tags Key=Name,Value=$stackname \
       Key=Service,Value=$stack \
       Key=Network,Value=$net \
       Key=Commit,Value=$(git rev-parse HEAD)"
fi

echo $tps | grep -q Peering           && ps="$ps ParameterKey=Peering,ParameterValue=$(peering)"
echo $tps | grep -q DBUsername        && ps="$ps ParameterKey=DBUsername,ParameterValue=$(randstring)"
echo $tps | grep -q DBPassword        && ps="$ps ParameterKey=DBPassword,ParameterValue=$(randstring)"

[ -n "$ps" ] && parameters="--parameters $ps"
##


##
# action
echo "${action} $stackname"
aws --profile $profile cloudformation $action-stack \
  --stack-name $stackname \
  --template-body file://$tpl \
  --output text \
  $tags \
  $capabilities \
  $parameters
s=$?
##

$w || exit $s


##
# wait for completion
event="IN_PROGRESS"

while [[ $event =~ IN_PROGRESS$ ]]; do
  sleep 5
  event=`aws --profile $profile cloudformation describe-stacks --stack-name $stackname --query Stacks[].StackStatus --output text 2>/dev/null`
  aws --profile $profile cloudformation describe-stack-events --stack-name $stackname --output text \
    --max-items=1 --query=StackEvents[].[LogicalResourceId,ResourceStatus] | head -n 1
done

echo $event
##
