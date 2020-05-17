#
#Updater script by RunningMango, ver1.0.
#
#Description:
#This script made for parsing timestamp, generating DerpFest zip name
# (assuming it was built today) and updating Updater-Stuff git repo
#
#Installing:
# $ mv updater.sh ~/updater.sh
# $ chmod +x updater.sh
# After this, edit lines 1-5 to match your device and paths and run.
#
#Note: check case of (c/C)hangelog.txt in line 41! It should match
# your git changelog.txt
#


gitPath='Updater-Stuff'		#Path to git repo folder (~/Updater-Stuff/<devices>)
device='wayne'
android='10'
buildtype="Official"
workdir='derpfest'		#Path to sources (~/derpfest/<sources>)

cd $gitPath/$device
git fetch --all			#Get last version of git repo
git pull

date=$(date -d "$D" '+%Y')$(date -d "$D" '+%m')$(date -d "$D" '+%d')
timestamp=`sed -n 8p /home/$USER/$workdir/out/target/product/$device/ota_metadata | cut -d'=' -f2`
package='DerpFest-'$android'-'$buildtype'-'$device'-'$date'.zip'
rm $device.json
echo '{
  "response": [
    {
      "datetime": '$timestamp',
      "filename": "'$package'"
    }
  ]
}' >> $device.json
rm changelog.txt
cp /home/$USER/$workdir/out/target/product/$device/Changelog.txt changelog.txt	#Check case here!

git add .
git commit -m $device': '$(date -d "$D" '+%Y')'-'$(date -d "$D" '+%m')'-'$(date -d "$D" '+%d')' update'
git push
