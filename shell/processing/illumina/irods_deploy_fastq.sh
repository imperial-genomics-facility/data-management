#!/bin/bash
#
# script to run irods_deploy_fastq 
#

#PBS -l walltime=72:00:00
#PBS -l select=1:ncpus=1:mem=1024mb

#PBS -m ea
#PBS -M igf@imperial.ac.uk
#PBS -j oe

#PBS -q pqcgi


#now
NOW="date +%Y-%m-%d%t%T%t"

#today
TODAY=`date +%Y-%m-%d`

############################ XXXXXXXXXXXXXX
DEPLOYMENT_SERVER=eliot.med.ic.ac.uk
DEPLOYMENT_BASE_DIR=/www/html/report/project
DEPLOYMENT_TAR_BASE_DIR=/data/www/html/report/data

#set up script
PATH_PROJECT_TAG_DIR=#pathProjectTagDir
SEQ_RUN_DATE=#seqRunDate
SEQ_RUN_NAME=#seqRunName
RUN_DIR_BCL2FASTQ=#runDirBcl2Fastq
CUSTOMER_FILE_PATH=#customerFilePath
PROJECT_TAG=#projectTag
MAIL_TEMPLATE_PATH=#mailTemplatePath
PATH_TO_DESTINATION=#pathToDestination
USE_IRODS=#useIrods
HIGHTLIGHT="iRODSUserTagging:Star"

IRODS_USER=igf
IRODS_PWD=igf
SEND_EMAIL_SCRIPT=$MAIL_TEMPLATE_PATH/../shell/processing/illumina/send_email.sh
SEND_NOTIFICATION_SCRIPT=$MAIL_TEMPLATE_PATH/../shell/processing/illumina/send_notification.sh

#ADDING FASTQ FILES TO WOOLF(woolfResc)
module load irods/4.2.0
iinit igf

echo "`$NOW` genereting global SampleSheet for the project ..."
ssh login.cx1.hpc.ic.ac.uk "cd $PATH_TO_DESTINATION; cat $SEQ_RUN_DATE/*/SampleSheet.* | grep -v FCID > $SEQ_RUN_DATE/SampleSheet.csv"	


echo "`$NOW` tarring the archive of $SEQ_RUN_DATE ..."
ssh login.cx1.hpc.ic.ac.uk "cd $PATH_TO_DESTINATION; tar hcfz $SEQ_RUN_DATE.tar.gz  $SEQ_RUN_DATE"	

echo "`$NOW` tar of $SEQ_RUN_DATE completed"

#generate an md5 checksum for the tarball
#need to change to location of archive to generate md5
echo "`$NOW` Generating md5 checksum for TAR archive..."
ssh login.cx1.hpc.ic.ac.uk "cd $PATH_TO_DESTINATION; md5sum $SEQ_RUN_DATE.tar.gz > $SEQ_RUN_DATE.tar.gz.md5; chmod 664 $SEQ_RUN_DATE.tar.gz $SEQ_RUN_DATE.tar.gz.md5"
echo "`$NOW` md5 checksum Generated"

#change to location where the tar and the md5 file are & check 
MD5_STATUS=`ssh login.cx1.hpc.ic.ac.uk "cd $PATH_TO_DESTINATION; md5sum -c $SEQ_RUN_DATE.tar.gz.md5 2>&1 | head -n 1 | cut -f 2 -d ' '"`
echo  $MD5_STATUS

#abort if md5 check fails
if [[ $MD5_STATUS == 'FAILED' ]]
then
        #send email alert...
        echo -e "subject:Sequencing Run $SEQ_RUN_NAME TAR Processing Error - MD5 check failed\nThe MD5 check for the file transfer of sequencing run $SEQ_RUN_NAME failed. Processing aborted." | sendmail -f igf -F "Imperial BRC Genomics Facility" "igf@ic.ac.uk"

        #...and exit
        exit 1
fi

#now send mail to the customer
customers_info=`grep -w $PROJECT_TAG $CUSTOMER_FILE_PATH/customerInfo.csv`
customer_name=`echo $customers_info|cut -d ',' -f2`
customer_username=`echo $customers_info|cut -d ',' -f3`
customer_passwd=`echo $customers_info|cut -d ',' -f4`
customer_email=`echo $customers_info|cut -d ',' -f5`

echo "UTENTE $customer_username"
# check if is internal customer
ldapUser=`ldapsearch -x -h unixldap.cc.ic.ac.uk | grep "uid: $customer_username"`
retval=$?
if [ $retval -ne 0 ]; then
    echo "External customer"
    externalUser="Y"
fi

if [ "$USE_IRODS" = "T" ]
then
######################## XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

	echo "$NOW checking if user already exists ..."
	irods_user=`iadmin lu | grep $customer_username | cut -d "#" -f1`
	echo "$NOW irods_user $irods_user"
	# if the user has not yet been created, then we create him
	if [ "$irods_user" = "" ]
	then
		echo "$NOW creating user ..."
		# make user
		iadmin mkuser $customer_username#igfZone rodsuser
		#external user set a password
		if [ "$externalUser" = "Y" ]; then
			iadmin moduser $customer_username#igfZone password $customer_passwd
		fi
	fi
	ichmod -M own igf /igfZone/home/$customer_username
	ichmod -r inherit /igfZone/home/$customer_username

	# creates the deploy structure
	imkdir -p /igfZone/home/$customer_username/$PROJECT_TAG/fastq/$SEQ_RUN_DATE

	ichmod -M own igf /igfZone/home/$customer_username/$PROJECT_TAG/fastq/$SEQ_RUN_DATE
	ichmod -r inherit /igfZone/home/$customer_username/$PROJECT_TAG/fastq/$SEQ_RUN_DATE
	echo "$NOW attaching meta-data run_name to run_date collection ..."
	imeta add -C /igfZone/home/$customer_username/$PROJECT_TAG/fastq/$SEQ_RUN_DATE run_name $SEQ_RUN_NAME

	echo "$NOW storing file in irods .... checksum"
	iput -k -fP -N 4 -X $PATH_TO_DESTINATION/restartFile.$PROJECT_TAG --retries 3 -R woolfResc $PATH_TO_DESTINATION/$SEQ_RUN_DATE.tar.gz  /igfZone/home/$customer_username/$PROJECT_TAG/fastq/$SEQ_RUN_DATE
	retval=$?
        if [ $retval -ne 0 ]; then
                echo "`$NOW` ERROR registering sequencing data in IRODS"
		echo -e "subject:Sequencing Data for project $PROJECT_TAG Processing Error. Processing aborted." | sendmail -f igf -F "Imperial BRC Genomics Facility" "igf@ic.ac.uk"

                exit 1
        fi

	iput -fP -R woolfResc $PATH_TO_DESTINATION/$SEQ_RUN_DATE.tar.gz.md5  /igfZone/home/$customer_username/$PROJECT_TAG/fastq/$SEQ_RUN_DATE

	#set expire date
	isysmeta mod /igfZone/home/$customer_username/$PROJECT_TAG/fastq/$SEQ_RUN_DATE/$SEQ_RUN_DATE.tar.gz '+30d'
	imeta add -d /igfZone/home/$customer_username/$PROJECT_TAG/fastq/$SEQ_RUN_DATE/$SEQ_RUN_DATE.tar.gz "$TODAY - fastq - $PROJECT_TAG" $customer_username $HIGHTLIGHT
	imeta add -d /igfZone/home/$customer_username/$PROJECT_TAG/fastq/$SEQ_RUN_DATE/$SEQ_RUN_DATE.tar.gz retention "30" "days"

#	ichmod -r read $customer_username /igfZone/home/$customer_username/

######################## END XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
else
	deployment_symbolic_link=$DEPLOYMENT_BASE_DIR/$PROJECT_TAG
	ssh $DEPLOYMENT_SERVER "mkdir -m 770 -p $deployment_symbolic_link"
	path_2_fastq=$deployment_symbolic_link/fastq
	#checks if in project_tag  already exists fastq directory
	# if yes: Add new files in that directory
	# if no: generate rnd direcory name and create fastq symbolic link to it
	if ssh $DEPLOYMENT_SERVER "[ -d /$path_2_fastq ]";then
		echo "`$NOW` coping TAR archive on eliot server ..."
		scp -r $PATH_TO_DESTINATION/$SEQ_RUN_DATE.tar.gz* $DEPLOYMENT_SERVER:$path_2_fastq
	else
		# creates rnd name for result directory
		rnddir_results=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-15} | head -n 1` 
		PATH_TO_RNDDIR=$DEPLOYMENT_TAR_BASE_DIR/$rnddir_results
		ssh $DEPLOYMENT_SERVER "mkdir -m 775 -p $PATH_TO_RNDDIR" 
	
		echo "`$NOW` coping TAR archive on eliot server ..."
		scp -r $PATH_TO_DESTINATION/$SEQ_RUN_DATE.tar.gz* $DEPLOYMENT_SERVER:$PATH_TO_RNDDIR 
		#create project_tag dir & symbolic link
		ssh $DEPLOYMENT_SERVER "ln -s  $PATH_TO_RNDDIR $path_2_fastq"
	fi
fi

#now remove the tar file
echo "`$NOW` remove tar from eliot server ..."
ssh login.cx1.hpc.ic.ac.uk "rm $PATH_TO_DESTINATION/$SEQ_RUN_DATE.tar.gz*" 
echo "`$NOW` Files have been deployed, Well done!"

if [[ $customer_email != *"@"* ]]; then
	#send email alert...
	echo -e "subject:Sequencing Run $SEQ_RUN_NAME Deploying Warning - the email address for $customer_username is unknown." | sendmail -f igf -F "Imperial BRC Genomics Facility" "igf@ic.ac.uk"
fi
#Prepare the email to send to the customer
customer_mail=customer_mail.$PROJECT_TAG
if [[ $externalUser == "Y" ]]; then
	if [ "$USE_IRODS" = "T" ]
	then
		cp $MAIL_TEMPLATE_PATH/eirodscustomer_mail.tml $RUN_DIR_BCL2FASTQ/$customer_mail
	else
		cp $MAIL_TEMPLATE_PATH/ecustomer_mail.tml $RUN_DIR_BCL2FASTQ/$customer_mail
	fi
else
	if [ "$USE_IRODS" = "T" ]
	then
		cp $MAIL_TEMPLATE_PATH/iirodscustomer_mail.tml $RUN_DIR_BCL2FASTQ/$customer_mail
	else
		cp $MAIL_TEMPLATE_PATH/icustomer_mail.tml $RUN_DIR_BCL2FASTQ/$customer_mail
	fi
fi
chmod 770 $RUN_DIR_BCL2FASTQ/$customer_mail
sed -i -e "s/#customerEmail/$customer_email/" $RUN_DIR_BCL2FASTQ/$customer_mail
sed -i -e "s/#customerName/$customer_name/" $RUN_DIR_BCL2FASTQ/$customer_mail
sed -i -e "s/#customerUsername/$customer_username/" $RUN_DIR_BCL2FASTQ/$customer_mail
sed -i -e "s/#passwd/$customer_passwd/" $RUN_DIR_BCL2FASTQ/$customer_mail
sed -i -e "s/#projectName/$PROJECT_TAG/" $RUN_DIR_BCL2FASTQ/$customer_mail
sed -i -e "s/#projectRunDate/$SEQ_RUN_DATE/g" $RUN_DIR_BCL2FASTQ/$customer_mail

customer_email=$RUN_DIR_BCL2FASTQ/$customer_mail
send_email_script=$RUN_DIR_BCL2FASTQ/send_email.${PROJECT_TAG}.sh
cp $SEND_EMAIL_SCRIPT $send_email_script
chmod 770 $send_email_script

sed -i -e "s/#customerEmail/${customer_email//\//\\/}/" $send_email_script
sed -i -e "s/#customerUsername/$customer_username/" $send_email_script
log_output_path=`echo $send_email_script | perl -pe 's/\.sh/\.log/g'`
echo -n "" > $log_output_path
echo -n "`$NOW`submitting send email to the customer job: " 
echo "$send_email_script"

#Prepare the email to send to Lab head & IGF to notify that new data are ready
#notification_mail=$RUN_DIR_BCL2FASTQ/notification_mail.$PROJECT_TAG
#send_notification_script=$RUN_DIR_BCL2FASTQ/send_notification.${PROJECT_TAG}.sh
#cp $SEND_NOTIFICATION_SCRIPT  $send_notification_script
#sed -i -e "s/#notificationEmail/${notification_mail//\//\\/}/" $send_notification_script
#log_notification_path=`echo $send_notification_script | perl -pe 's/\.sh/\.log/g'`
#chmod 770 $send_notification_script

#cp $MAIL_TEMPLATE_PATH/notification_dissemination_mail.tml $notification_mail
#chmod 770 $RUN_DIR_BCL2FASTQ/$notification_mail
#sed -i -e "s/#projectName/$PROJECT_TAG/" $notification_mail
#sed -i -e "s/#sendEmailScript/${send_email_script//\//\\/}/" $notification_mail

#send to Lab head & IGF to notify that new data are ready
#job_id=null
#job_id=`qsub -o $log_notification_path -j oe $send_notification_script`
#echo "qsub -o $log_notification_path -j oe $send_notification_script"
#echo "`$NOW`Job ID:$job_id"
#chmod 660 $log_notification_path

#Before to send the email to the customer the invoice has to be paid!!!
#send to the customer
job_id=null
job_id=`qsub -o $log_output_path -j oe $send_email_script`
echo "qsub -o $log_output_path -j oe $send_email_script"
#echo "`$NOW`Job ID:$job_id"
chmod 660 $log_output_path


disseminate=`grep $PROJECT_TAG $RUN_DIR_BCL2FASTQ/*.discard | cut -d "," -f10 | sort | uniq | wc -l`
#disseminate=0
if [ "$disseminate" -eq 0 ]; then
	#sendmail -t < $RUN_DIR_BCL2FASTQ/$customer_mail 
	echo "SEND_EMAIL"
else
	# Prepare and send email with reads under the threshold
	discard_mail=discard_mail_$SEQ_RUN_NAME.$PROJECT_TAG
	cp $MAIL_TEMPLATE_PATH/discard_mail.tml $RUN_DIR_BCL2FASTQ/$discard_mail	
	echo "SEQUENCE RUN NAME $SEQ_RUN_NAME" >>  $RUN_DIR_BCL2FASTQ/$discard_mail
	echo "PROJECT NAME  $PROJECT_TAG" >>  $RUN_DIR_BCL2FASTQ/$discard_mail
	`grep $PROJECT_TAG $RUN_DIR_BCL2FASTQ/*.discard >> $RUN_DIR_BCL2FASTQ/$discard_mail`
	sendmail -t < $RUN_DIR_BCL2FASTQ/$discard_mail 
	echo "NO SEND_EMAIL"
fi
#now remove 
#rm $RUN_DIR_BCL2FASTQ/$customer_mail
#sed -i /$PROJECT_TAG/d $CUSTOMER_FILE_PATH/customerInfo.csv
