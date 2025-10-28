#!/bin/bash

###########################################################################################################################
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
###########################################################################################################################
#
# This script uses Bart Reardon's swiftDialog for user dialogs:
# https://github.com/bartreardon/swiftDialog
#
############################################################################################################################
#
# Created by Sebastien Del Saz Alvarez on 29 August 2025
#
###########################################################################################################################
#Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

#Check http response
checkResponse() {
local http_code
http_code=$(curl -s -o /dev/null -w "%{http_code}" "$@")
local url="${!#}"
  
if [[ $http_code =~ ^(200|201|202|204)$ ]]; then
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Command successfully sent: HTTP code: $http_code" >> "$Logfile"
else
echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Command failed with HTTP error $http_code" >> "$Logfile"
case $http_code in
      400) echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Bad Request" >> "$Logfile" ;;
      401) echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Unauthorized – check your credentials." >> "$Logfile" ;;
      403) echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Forbidden – Insufficient privileges." >> "$Logfile" ;;
      404) echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Not Found – resource does not exist." >> "$Logfile" ;;
      409) echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Conflict – resource may already exist." >> "$Logfile" ;;
      500) echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Server Error – try again later." >> "$Logfile" ;;
      *)   echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Unexpected HTTP response: $http_code" >> "$Logfile" ;;
esac
fi
echo "$http_code"
}

#Create the logfile
Logfile=/var/log/JSS-Framework-Fixer.log
touch $Logfile

#Dialog variables
messageFont="size=18,name=HelveticaNeue"
titleFont="weight=bold,size=30,name=HelveticaNeue-Bold"
icon="https://github.com/Sdelsaz/JSS-Framework-Fixer/raw/main/images/icon1.png"

#######################################################################################################
#Check if Swift Dialog is installed. if not, Install it
#######################################################################################################
echo "######################################START LOGGING#############################################
$(
date '+%Y-%m-%d %H:%M:%S') INFO: Checking if SwiftDialog is installed" >> $Logfile
if [[ -e "/usr/local/bin/dialog" ]]
then
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: SwiftDialog is already installed" >> $Logfile
else
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: SwiftDialog Not installed, downloading and installing" >> $Logfile
/usr/bin/curl https://github.com/swiftDialog/swiftDialog/releases/download/v2.5.5/dialog-2.5.5-4802.pkg -L -o /tmp/dialog-2.5.5-4802.pkg >> $Logfile
cd /tmp
/usr/sbin/installer -pkg dialog-2.5.5-4802.pkg -target / >> $Logfile
fi

#######################################################################################################
# Prompt functions
#######################################################################################################
#Prompt to choose Authentication Method
authMethodPrompt() {
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Asking to select an authentication method" >> $Logfile
  
  AuthMethod=$(/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Hi!  

How would you like to authenticate?" \
--radio "groupSelection" \
--selecttitle "Please select an option",radio --selectvalues "User Account & Password, API Client & Secret" \
--icon "$icon" \
--alignment "left" \
--button2 \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--infobuttontext "Required Privileges" \
--infobuttonaction "https://github.com/Sdelsaz/JSS-Framework-Fixer?tab=readme-ov-file#requirements" \
--small)
if [ $? -ne 0 ]
then
echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: User Cancelled" >> $Logfile
invalidateToken
exit 0
fi
authSelection=$(echo $AuthMethod | awk -F '"' '{print $4}')
if [[ $authSelection == "User Account & Password" ]]
then
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Selected authentication method: User Account & Password" >> $Logfile
userNameLabel="User Name"
passwordLabel="Password"
authMethod="usercreds"
else
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Selected authentication method: API Client & Secret" >> $Logfile
userNameLabel="Client ID"
passwordLabel="Client Secret"
authMethod="clientsecret"
fi
}
#Prompt for User Account and Password
credentialPrompt() {
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Prompting for credentials and server url" >> $Logfile
serverDetails=$(/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Please enter your Jamf Pro details below:" \
--textfield "Jamf Pro URL","required" : true \
--textfield "$userNameLabel",required : true \
--textfield "$passwordLabel","secure : true,required : true" \
--icon "$icon" \
--alignment "left" \
--small \
--button2 \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--json)
if [ $? == 0 ]
then
jssurl=$(echo "$serverDetails" | /usr/bin/plutil -extract "Jamf Pro URL" xml1 -o - - | xmllint --xpath "string(//string)" -)
userName=$(echo "$serverDetails" | /usr/bin/plutil -extract "$userNameLabel" xml1 -o - - | xmllint --xpath "string(//string)" -)
APIpassword=$(echo "$serverDetails" | /usr/bin/plutil -extract "$passwordLabel" xml1 -o - - | xmllint --xpath "string(//string)" -)
else
echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: User Cancelled" >> $Logfile
exit 0
fi
if [[ $jssurl != *"https://"* ]]
then 
jssurl="https://$jssurl"
fi
}

#Prompt explaining there was an issue with the server details/credentials
invalidCredentialsPrompt() {
  /usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Oops! We were unable to validate the provided URL or credentials. Please make sure that the server is reachable and that the server URL and credentials are correct." \
--icon "$icon" \
--overlayicon "caution" \
--alignment "left" \
--small \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--button1text "OK"
}

#Prompt to choose new or existing group
groupOptionPrompt() {
groupOptions=$(/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Would you like to create a Smart Computer Group to redeploy the Jamf Management Framework to?" \
--radio "groupSelection" \
--selecttitle "Please select an option",radio --selectvalues "I already have a Smart Computer Group, Please create a Smart Computer Group" \
--icon "$icon" \
--alignment "left" \
--button2 \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--small)
if [ $? == 0 ]
then
groupSelection=$(echo $groupOptions | awk -F '"' '{print $4}')
else
echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: User Cancelled" >> $Logfile
invalidateToken
exit 0
fi
}

#Prompt for group name
groupNamePrompt() {
groupName=$(/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Please enter the name of the Smart Computer Group. Watch out for typos!" \
--textfield "Group Name" \
--icon "$icon" \
--alignment "left" \
--small \
--button2 \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--json)
if [ $? == 0 ]
then
groupName=$(echo "$groupName" | awk -F '"' '{print $4}' | tr -d '\r\n' | sed 's/[^[:print:]]//g')
else
echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: User Cancelled" >> $Logfile
invalidateToken
exit 0
fi
#Replace spaces with %20 for API call
groupName2=$(echo $groupName | sed 's/ /%20/g')
#Check to make sure a group with the provided name exists
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Checking if a group called $groupName exists" >> $Logfile

groupCheck=$(checkResponse -X 'GET' "$jssurl/api/v2/computer-groups/smart-groups?page=0&page-size=100&sort=id%3Aasc&filter=name%3D%3D%22${groupName2}%22" -H "accept: application/json" -H "Authorization: Bearer ${bearerToken}")
if [[ $groupCheck =~ ^(200|201|202|204)$ ]]; then
groupCheck=$(curl -X 'GET' "$jssurl/api/v2/computer-groups/smart-groups?page=0&page-size=100&sort=id%3Aasc&filter=name%3D%3D%22${groupName2}%22" -H "accept: application/json" -H "Authorization: Bearer ${bearerToken}")
else
echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Could not check if a group called $groupName exists" >> $Logfile
errorPrompt
invalidateToken
exit 1
fi
if [[ $(echo "$groupCheck" | jq -r '.totalCount') -eq 0 ]]; then
echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: No group with name $groupName found" >> $Logfile
groupNotFound
else
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Group with name $groupName found" >> $Logfile
fi
}

#Prompt explaining the group was not found
groupNotFound() {
/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Oops! We could not find a Smart Computer Group called ${groupName}" \
--icon "$icon" \
--overlayicon "caution" \
--alignment "left" \
--small \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--button1text "OK"

groupNamePrompt
}

#Prompt explaining a grouo with the provided name already exists
groupExists() {
/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Oops! It looks like there is already a Smart Computer Group called ${groupName}" \
--icon "$icon" \
--overlayicon "caution" \
--alignment "left" \
--small \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--button1text "OK"

newGroupPrompt
}

#Prompt for number of days since last Inventory Update
daysPrompt() {
days=$(/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "OK, we will create a Smart Computer Group based on the number of days since the last Inventory Update. Please enter the number of days." \
--textfield "Number of days","regex=\d,regexerror=Input must be a number,required : true" \
--icon "$icon" \
--alignment "left" \
--small \
--button2 \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--json)
if [ $? == 0 ]; then
days=$(echo $days | awk -F '"' '{print $4}')
else
echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: User Cancelled" >> $Logfile
invalidateToken
exit 0
fi
}

#Request the name of the Smart Computer Group to be created
newGroupPrompt() {
groupName=$(/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Please enter a name for the new Smart Computer Group." \
--textfield "Group Name","required" : true \
--icon "$icon" \
--alignment "left" \
--small \
--button2 \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--json)
if [ $? == 0 ]; then
groupName=$(echo "$groupName" | awk -F '"' '{print $4}'| tr -d '\r\n' | sed 's/[^[:print:]]//g')
else
echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: User Cancelled" >> $Logfile
invalidateToken
exit 0
fi
#Replace spaces with %20 for API call
groupName2=$(echo $groupName | sed 's/ /%20/g')
#Check to make sure a group with the provided name does not already exists
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Checkin if a group called $groupName already exists" >> $Logfile
groupCheck=$(checkResponse -X 'GET' "$jssurl/api/v2/computer-groups/smart-groups?page=0&page-size=100&sort=id%3Aasc&filter=name%3D%3D%22${groupName2}%22" -H "accept: application/json" -H "Authorization: Bearer ${bearerToken}")
if [[ $groupCheck =~ ^(200|201|202|204)$ ]]; then
groupCheck=$(curl -X 'GET' "$jssurl/api/v2/computer-groups/smart-groups?page=0&page-size=100&sort=id%3Aasc&filter=name%3D%3D%22${groupName2}%22" -H "accept: application/json" -H "Authorization: Bearer ${bearerToken}")
else
echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Could not check if a group called $groupName already exists" >> $Logfile
errorPrompt
invalidateToken
exit 1
fi

if [[ $(echo "$groupCheck" | jq -r '.totalCount') -eq 1 ]]; then
echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: There is already a Smart Computer Group named $groupName" >> $Logfile
groupExists
fi
}

#Wait for the group to be created and replication to all nodes
creationPrompt() {
/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Please wait for the creation to complete and replicate to all nodes of your Jamf Pro instance" \
--timer 60 \
--icon "$icon" \
--alignment "left" \
--small \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--button1text "Cancel"
if [ $? == 0 ]; then
echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: User Cancelled" >> $Logfile
invalidateToken
exit 0
fi
}

#Pormpt to indicate there are no members in the Smart Computer Group
noMembersPrompt() {
/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "There are 0 members in this Smart Computer Group.  No action required." \
--icon "$icon" \
--alignment "left" \
--small \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--button1text "OK"
if [ $? != 0 ]; then
echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: User Cancelled" >> $Logfile
invalidateToken
exit 0
fi
invalidateToken
}

#Show number of devices in the Smart Computer Group and ask if we should remeidate
remediationPrompt() {
remediationCheck=$(/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "There are $memberCount members in the Smart Computer Group.  Would you like to redeploy the Jamf Management Framework on all computers in this group?" \
--icon "$icon" \
--alignment "left" \
--small \
--button1text "No" \
--button2text "Yes" \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--json)
if [ $? == 2 ]; then
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Remediation choice: yes" >> $Logfile
remediationCheck="Yes"
else
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Remediation choice: No. Exiting." >> $Logfile
invalidateToken
exit 0
fi
}

redeploymentPrompt() {
#Create a command file (needed to close the dialog later if needed)
commandFile="/var/tmp/dialogIndeterminate.txt"
: > "$commandFile"

/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "We're working on it! This can take a while depending on how many computers are in the Smart Computer Group" \
--icon "$icon" \
--alignment "left" \
--small \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--button1text "Cancel" \
--progress --indeterminate \
--commandfile "$commandFile" &

dialogPID=$!
if [ $? != 0 ]; then
echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: User Cancelled" >> $Logfile
invalidateToken
exit 0
fi
}
  
errorPrompt() {
/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Oops! An error occurred. please check $Logfile for more details" \
--icon "$icon" \
--overlayicon "caution" \
--alignment "left" \
--small \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--button1text "OK"
if [ $? != 0 ]; then
invalidateToken
exit 1
fi
}

#End prompt
donePrompt() {
/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "We're done!  

The command the redeploy the Jamf Management Framework has been deployed to all members of the Smart Computer Group." \
--icon "$icon" \
--alignment "left" \
--small \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--button1text "OK"
}


#######################################################################################################
# Bearer Token functions
#######################################################################################################
#Variable declarations for bearer token
bearerToken=""
tokenExpirationEpoch="0"

getBearerToken() {
if [[ $authMethod == "usercreds" ]]; then
response=$(curl -s -u "$userName":"$APIpassword" "$jssurl"/api/v1/auth/token -X POST)
bearerToken=$(echo "$response" | plutil -extract token raw -)
tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
checkTokenExpirationreprompt
fi
if [[ $authMethod == "clientsecret" ]]; then
response=$(curl --silent --location --request POST "$jssurl/api/oauth/token" \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${userName}" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_secret=${APIpassword}")
bearerToken=$(echo "$response" | plutil -extract access_token raw -)
tokenExpiration=$(echo "$response" | plutil -extract expires_in raw -)
nowEpochUTC=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
tokenExpirationEpoch=$(($nowEpochUTC + $tokenExpiration - 1))
checkTokenExpirationreprompt
fi
}

checkTokenExpirationreprompt() {
nowEpochUTC=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
if [[ tokenExpirationEpoch -gt nowEpochUTC ]]
then
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Token valid until the following epoch time: " "$tokenExpirationEpoch" >> $Logfile
else
echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Unable to validate server details/credentials" >> $Logfile
invalidCredentialsPrompt
credentialPrompt
getBearerToken
fi
}
  
checkTokenExpiration() {
nowEpochUTC=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
if [[ tokenExpirationEpoch -gt nowEpochUTC ]]
then
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Token valid until the following epoch time: " "$tokenExpirationEpoch" >> $Logfile
else
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: No Token available. Getting new token." >> $Logfile
getBearerToken
fi
}

invalidateToken() {
responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" $jssurl/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
if [[ ${responseCode} == 204 ]]
then
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Token successfully invalidated" >> $Logfile
bearerToken=""
tokenExpirationEpoch="0"
elif [[ ${responseCode} == 401 ]]
then
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Token already invalid" >> $Logfile
else
echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: An unknown error occurred invalidating the token" >> $Logfile
fi
}

#######################################################################################################
#Prompt for authentication method
authMethodPrompt

#Prompt for credentials
credentialPrompt

#Prompt for credentials
getBearerToken

#Prompt to choose new or existing group
groupOptionPrompt
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Prompting to choose between new group of existing group" >> $Logfile

#Check if a Smart Cmputer Group already exists
if [[ "$groupSelection" == "I already have a Smart Computer Group" ]]; then
	
#Request the name of the existing Smart Computer Group
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Existing group workflow selected.  Prompting for existing group name" >> $Logfile
groupNamePrompt

fi

#Check if we need to create a Smart Computer Group 
if [[ "$groupSelection" == "Please create a Smart Computer Group" ]]; then
	
#Prompt for number of days since last Inventory Update
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: New group workflow selected. Prompting for number of days since last Inventory Update" >> $Logfile
daysPrompt

#Request the name of the Smart Computer Group to be created
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Prompting for new group name" >> $Logfile
newGroupPrompt


# Create the JSON payload for the smart group
read -r -d '' JSON_PAYLOAD << EOM
{
  "name": "${groupName}",
  "criteria": [
    {
      "name": "Last Inventory Update",
      "priority": 0,
      "andOr": "and",
      "searchType": "more than x days ago",
      "value": "${days}",
      "openingParen": false,
      "closingParen": false
    }
  ],
  "siteId": "-1"
}

EOM
  
# Create the Smart Computer Group
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Creating group called $groupName" >> "$Logfile"

groupCreation=$(checkResponse -X 'POST' \
  "$jssurl/api/v2/computer-groups/smart-groups" -H "accept: application/json" -H "Authorization: Bearer ${bearerToken}" -H "Content-Type: application/json" -d "${JSON_PAYLOAD}")
if [[ $groupCreation =~ ^(200|201|202|204)$ ]]; then
echo "done"
else
echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Group creation failed" >> $Logfile
errorPrompt
invalidateToken
exit 1
fi

#Wait for replication to all server nodes
creationPrompt
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Waiting for replication" >> $Logfile

#Check Token expiration
checkTokenExpiration

#Replace spaces with %20 for API call
groupName2=$(echo $groupName | sed 's/ /%20/g')

fi

#Get the members of the Smart Computer Group
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Checking members of the group" >> $Logfile
memberList=$(curl -X 'GET' -H "Authorization: Bearer ${bearerToken}" "$jssurl/JSSResource/computergroups/name/$groupName2" -H "accept: application/xml" |  xmllint --format - |  grep -A3 "<computer>" | awk -F '[<>]' '/id/{print $3}')

#Count the members
memberCount="0"
for item in $memberList; do
memberCount=$(( memberCount +1 ))
done
  
#Prompt explaining no computers were found
if [ -z "$memberList" ]; then
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: There are 0 members in the group" >> $Logfile
noMembersPrompt
else

#Show number of devices in the Smart Computer Group and ask if we should remedidate
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: There are $memberCount members in the group" >> $Logfile
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Checking if remediation is desired" >> $Logfile
remediationPrompt

if  [[ $remediationCheck == "Yes" ]]; then

#Show Progreess bar while the Jamf Management Framework is being redeployed on the computers
redeploymentPrompt

#Loop through the members of the Smart Computer Group and renew the Jamf Management Framework
for computer in $memberList; do
	
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Redeploying Jamf Management Framework on Computer with ID: $computer" >> $Logfile
checkResponse -X 'POST' -H "Authorization: Bearer ${bearerToken}" "$jssurl/api/v1/jamf-management-framework/redeploy/$computer" -H 'accept: application/json' -d ''
#Update the dialog
echo "progresstext: "Redeploying Jamf Management Framework on Computer with ID: $computer > "$commandFile"
sleep 1
checkTokenExpiration
done

#Close the progress dialog
pkill Dialog

#Clean up
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Cleaning up ..." >> $Logfile
rm /var/tmp/dialogIndeterminate.txt
fi
invalidateToken
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Done!" >> $Logfile
donePrompt
fi
exit 0
