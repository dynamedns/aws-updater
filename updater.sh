#!/bin/bash
#
# Dyname Updater for Ubuntu/RedHat instances on AWS

# Our API location
API_PROTOCOL="https"
API_HOSTNAME="api.dyname.net"
API_VERSION="v1"
API="$API_PROTOCOL://$API_HOSTNAME/$API_VERSION"

echo "Dyname Updater for AWS"

# We'll need either curl or wget to rock.
if [[ -x `which curl` ]]; then
    DLCMD="curl"
    DLARG="-s"
elif [[ -x `which wget` ]]; then
    DLCMD="wget"
    DLARG="-qO-"
else
    echo "Sorry, this script requires either curl or wget installed and in PATH."
    exit 1
fi

if [[ "$EMAIL" == "" ]]; then
    echo "Error: No e-mail specified, Dyname updater cannot function."
    exit 1
fi

# Get instance id and region from AWS metadata
INSTANCE_ID=$($DLCMD $DLARG curl http://169.254.169.254/latest/meta-data/instance-id)
REGION=$($DLCMD $DLARG http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}')

if [[ "$INSTANCE_ID" != "i-"* ]]; then
    echo "Error: Cannot get instance ID, are you sure we're running in AWS?"
    echo "For a Dyname updater script usable outside AWS, see https://dyname.net"
    exit 1
fi

if [[ -x `which apt-get` ]]; then
    # We're running Ubuntu/Debian/something else with apt
    sudo apt-get -qq update
    sudo apt-get -qqy install awscli

elif [[ -x `which yum` ]]; then
    # CentOS / RHEL
    sudo yum -y install awscli
else
    echo "Error: Cannot determine which platform I'm running on. Please file a bug report at help@dyname.net."
    exit 1
fi

# Get account ID to create a secret hash
ACCOUNT_ID=$(aws ec2 describe-security-groups --region="$REGION" --group-names 'Default' --query 'SecurityGroups[0].OwnerId' --output text)
SECRET=$(echo $ACCOUNT_ID | md5sum | cut -d' ' -f1)

# Get the defined tag, defaulting to Name
if [[ "$HOSTNAME_TAG" == "" ]]; then
    HOSTNAME_TAG="Name"
fi
TAGGED_NAME=$(aws ec2 describe-tags --region="$REGION" --filters '[ { "Name": "resource-id", "Values": ["'"$INSTANCE_ID"'"] }, { "Name": "key" , "Values": ["'"$HOSTNAME_TAG"'"] } ]' --query 'Tags[0].Value' --output text)


if [[ "$TAGGED_NAME" != *"."* ]]; then
    echo "Error: Tag $HOSTNAME_TAG does not seem like a FQDN. Exiting."
    exit 1
fi

echo "Tagged hostname: $TAGGED_NAME"

EMAIL=${EMAIL//@/%}
UPDATER_URL="$API_PROTOCOL://$EMAIL:$SECRET@$API_HOSTNAME/nic/update?hostname=$TAGGED_NAME"

if [[ "$DLCMD" == "wget" ]]; then
    UPDATE_CMD="$DLCMD $DLARG --auth-no-challenge --http-user=$EMAIL --http-password=$SECRET \"$UPDATER_URL\""
else
    UPDATE_CMD="$DLCMD $DLARG \"$UPDATER_URL\""
fi

eval $UPDATE_CMD > /dev/null

if [[ $? -eq 0 ]]; then
    echo "Hostname created or updated successfully."
else
    echo "Error creating hostname."
fi

# Create an updater script
UPDATERFILE="$HOME/.dyname/updater.sh"
echo -e "#!/bin/bash\n# Dyname Updater\n$UPDATE_CMD\n" > $UPDATERFILE
chmod 755 $UPDATERFILE

# Every 7 days is enough for an AWS instance - the IP shouldn't change
CRONPATTERN="$(($RANDOM%59+0)) $(($RANDOM%23+0)) */7 * *"
echo -e "$(crontab -l 2>/dev/null)\n#-- Begin Dyname updater\n@reboot $UPDATERFILE\n$CRONPATTERN $UPDATERFILE\n#-- End Dyname updater" | crontab
