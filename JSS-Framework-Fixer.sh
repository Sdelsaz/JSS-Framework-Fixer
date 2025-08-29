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

#Dialog variables
messageFont="size=18,name=HelveticaNeue"
titleFont="weight=bold,size=30,name=HelveticaNeue-Bold"
icon="https://i.imgur.com/79AYkzG.png"

#Check if Swift Dialog is installed. if not, Install it
echo "Checking if SwiftDialog is installed"
if [[ -e "/usr/local/bin/dialog" ]]
then
echo "SwiftDialog is already installed"
else
echo "SwiftDialog Not installed, downloading and installing"
/usr/bin/curl https://github.com/swiftDialog/swiftDialog/releases/download/v2.5.5/dialog-2.5.5-4802.pkg -L -o /tmp/dialog-2.5.5-4802.pkg 
cd /tmp
/usr/sbin/installer -pkg dialog-2.5.5-4802.pkg -target /
fi

#######################################################################################################
# Prompt functions
#######################################################################################################
#Prompt for Credentoials
credentialPrompt() {
serverDetails=$(/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Please enter your Jamf Pro details below:" \
--textfield "Jamf Pro URL","required" : true \
--textfield "Username",required : true \
--textfield "Password","secure : true,required : true" \
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
userName=$(echo "$serverDetails" | /usr/bin/plutil -extract "Username" xml1 -o - - | xmllint --xpath "string(//string)" -)
APIpassword=$(echo "$serverDetails" | /usr/bin/plutil -extract "Password" xml1 -o - - | xmllint --xpath "string(//string)" -)
else
echo "User cancelled"
exit 0
fi
if [[ $jssurl != *"https://"* ]]
then 
jssurl="https://$jssurl"
fi
}

#Prompt to choose new or existing group
goupOptionPrompt() {
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
echo "User cancelled"
exit 0
fi
}

#Prompt for group name
groupNamePrompt() {
groupName=$(/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Please enter the name of the Smart Computer Group. Watch out for typos :-) " \
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
groupName=$(echo "$groupName" | awk -F '"' '{print $4}')
else
echo "User cancelled"
exit 0
fi
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
echo "User cancelled"
exit 0
fi
}
	
#Request the name of the Smart Computer Group to be created
newGroupPrompt() {
groupName=$(/usr/local/bin/dialog \
--title "JSS Framework Fixer" \
--message "Please enter a name of the new Smart Computer Group." \
--textfield "Group Name","required" : true \
--icon "$icon" \
--alignment "left" \
--small \
--button2 \
--messagefont "$messageFont" \
--titlefont "$titleFont" \
--json)
if [ $? == 0 ]; then
groupName=$(echo "$groupName" | awk -F '"' '{print $4}')
else
echo "User cancelled"
exit 0
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
echo "User cancelled"
exit 0
fi
}
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
echo "User cancelled"
exit 0
fi
}

# Show number of devices in the Smart Computer Group and ask if we should remeidate
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
remediationCheck="Yes"
else
echo "User cancelled"
exit 0
fi
}

#######################################################################################################
# Bearer Token functions
#######################################################################################################
#Variable declarations for bearer token
bearerToken=""
tokenExpirationEpoch="0"

getBearerToken() {
credentialPrompt
response=$(curl -s -u "$userName":"$APIpassword" "$jssurl"/api/v1/auth/token -X POST)
bearerToken=$(echo "$response" | plutil -extract token raw -)
tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
checkTokenExpiration
}

checkTokenExpiration() {
nowEpochUTC=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
if [[ tokenExpirationEpoch -gt nowEpochUTC ]]
then
echo "INFO: Token valid until the following epoch time: " "$tokenExpirationEpoch"
else
echo "INFO: No valid token available, getting new token"

getBearerToken
fi
}

invalidateToken() {
responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" $jssurl/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
if [[ ${responseCode} == 204 ]]
then
echo "INFO: Token successfully invalidated"
bearerToken=""
tokenExpirationEpoch="0"
elif [[ ${responseCode} == 401 ]]
then
echo "INFO: Token already invalid"
else
echo "ERROR: An unknown error occurred invalidating the token"
fi
}
#Check for existing token and prompt for credentials if needed
checkTokenExpiration

#Prompt to choose new or existing group
goupOptionPrompt

#Check if a Smart Cmputer Group already exist
if [[ "$groupSelection" == "I already have a Smart Computer Group" ]]; then
	
#Request the name of the existing Smart Computer Group
groupNamePrompt
#Replace spaces with %20 for API call
groupName=$(echo $groupName | sed 's/ /%20/g')

fi

#Check if we need to create a Smart Cmputer Group 
if [[ "$groupSelection" == "Please create a Smart Computer Group" ]]; then
	
#Prompt for number of days since last Inventory Update
daysPrompt

#Request the name of the Smart Computer Group to be created
newGroupPrompt

#Create the new Smart Cmputer Group
read -r -d '' XML_PAYLOAD << EOM
<computer_group>
  <name>${groupName}</name>
  <is_smart>true</is_smart>
  <site><name>None</name></site>
  <criteria>
    <criterion>
      <name>Last Inventory Update</name>
      <priority>0</priority>
      <and_or>and</and_or>
      <search_type>more than x days ago</search_type>
      <value>${days}</value>
    </criterion>
  </criteria>
</computer_group>
EOM

#Create the Smart Computer Group
curl -X 'POST' -H "Authorization: Bearer ${bearerToken}" "$jssurl/JSSResource/computergroups/id/0"  -H "Content-Type: application/xml" -d "$XML_PAYLOAD"

#Wait for replication to all server nodes
creationPrompt
#Replace spaces with %20 for API call
groupName=$(echo $groupName | sed 's/ /%20/g')

fi

#Get the members of the Smart Computer Group
memberList=$(curl -X 'GET' -H "Authorization: Bearer ${bearerToken}" "$jssurl/JSSResource/computergroups/name/$groupName" -H "accept: application/xml" |  xmllint --format - |  grep -A3 "<computer>" | awk -F '[<>]' '/id/{print $3}')

#Count the members
memberCount="0"
for item in $memberList; do
memberCount=$(( memberCount +1 ))
done
	
#Prompt explaining no computers were found
if [ -z "$memberList" ]; then
noMembersPrompt
else

# Show number of devioces in the Smart Computer Group and ask if we should remeidate
remediationPrompt

if  [[ $remediationCheck == "Yes" ]]; then

#Loop through the members of the SMart Computer Group and renew the Jamf Management Framework
	
for computer in $memberList; do
	
echo "Redeploying Jamf Management Framework on Computer with ID: $computer"
curl -X 'POST' -H "Authorization: Bearer ${bearerToken}" "$jssurl/api/v1/jamf-management-framework/redeploy/$computer" -H 'accept: application/json' -d ''

done
fi
fi
exit 0
