#!/bin/bash

set -xa

baseResourcesStackName=$1
shift

trackConfigName=$1
shift

skipRuns=${1:-0}
shift

# check that track config exists
trackExists=$( jq 'has('\"${trackConfigName}\"')' track-configs.json )

# get the trackName and runs array
trackConfig=$( jq -r '.'\"${trackConfigName}\" track-configs.json )
trackName=$( jq .track_name <<< $trackConfig )
runs=($( jq -r '.'\"${trackConfigName}\"'.runs' track-configs.json | tr -d '[]," ' ))

# make track config folders
mkdir -p routines/$trackConfigName

# generate each run
endMinutes=0
numRuns=${#runs[@]}
for (( i=0; i<${numRuns}; i++ ));
do
    # check if run skipped
    if [[ $i -lt $skipRuns ]]; then
        continue
    fi

    # get run config
    runTitle=${runs[$i]}
    runExists=$( jq 'has('\"${runTitle}\"')' run-configs.json )
    runConfig=$( jq -r '.'\"${runTitle}\" run-configs.json )
    
    # set run name and folder name
    runName=$( tr '_' '-' <<< $trackConfigName)-R$i
    prevRunName=$( tr '_' '-' <<< $trackConfigName)-R$((i-1))
    mkdir -p routines/$trackConfigName/$runName
    runFolder=routines/$trackConfigName/$runName

    # set timings (2 minute overlap)
    startMinutes=$(( $endMinutes ))
    durationMinutes=$( jq -r '.duration' <<< $runConfig )
    endMinutes=$(( $endMinutes + durationMinutes ))

    # create hyperparameters.json
    cp hyperparameters/$( jq -r .hyperparameters <<< $runConfig ).json $runFolder/hyperparameters.json

    # create model_metadata.json
    actionSpaceFile=$( jq -r '."action-space"' <<< $runConfig ).json
    jq --slurpfile actionSpace action-spaces/${actionSpaceFile} '.action_space |= $actionSpace[]' base/model_metadata.json > $runFolder/model_metadata.json

    # create reward_function.py
    cp reward-functions/$( jq -r '."reward-function"' <<< $runConfig ).py $runFolder/reward_function.py

    # create system.env
    cp base/system.env $runFolder/system.env
    sed -i "s/DR_WORKERS=/DR_WORKERS=$( jq -r .workers <<< $runConfig )/" $runFolder/system.env

    # create run.env
    cp base/run.env $runFolder/run.env
    sed -i "s/DR_RUN_NAME=/DR_RUN_NAME=$runName/" $runFolder/run.env
    sed -i "s/DR_WORLD_NAME=/DR_WORLD_NAME=$( jq -r '."track-name"' <<< $trackConfig )/" $runFolder/run.env
    sed -i "s/DR_TRAIN_ROUND_ROBIN_ADVANCE_DIST=/DR_TRAIN_ROUND_ROBIN_ADVANCE_DIST=$( jq -r '."round-robin"' <<< $runConfig )/" $runFolder/run.env
    sed -i "s/DR_UPLOAD_S3_PREFIX=/DR_UPLOAD_S3_PREFIX=upload\/$runName/" $runFolder/run.env
    
    # set clone parameters
    if [ $i -gt 0 ]
    then
        sed -i "s/DR_LOCAL_S3_PRETRAINED=False/DR_LOCAL_S3_PRETRAINED=True/" $runFolder/run.env
        sed -i "s/DR_LOCAL_S3_PRETRAINED_PREFIX=/DR_LOCAL_S3_PRETRAINED_PREFIX=$prevRunName/" $runFolder/run.env
        sed -i "s/DR_LOCAL_S3_PRETRAINED_CHECKPOINT=/DR_LOCAL_S3_PRETRAINED_CHECKPOINT=$( jq -r '."clone-checkpoint"' <<< $runConfig )/" $runFolder/run.env
    fi

    run validation
    set +x
    . ./validation.sh ${runFolder}
    set -x

    # find base stack s3 bucket
    BUCKET=$(aws cloudformation describe-stacks --stack-name $baseResourcesStackName | jq '.Stacks | .[] | .Outputs | .[] | select(.OutputKey=="Bucket") | .OutputValue' | tr -d '"') 

    # copy files to s3
    aws s3 cp ${runFolder} s3://${BUCKET}/custom_files/${runName} --recursive

    # create run stack
    instanceType=$( jq -r .instance <<< $runConfig )
    aws cloudformation deploy --stack-name $runName --parameter-overrides InstanceType=$instanceType ResourcesStackName=$baseResourcesStackName RunName=$runName StartMinutes=$startMinutes EndMinutes=$endMinutes --template-file spot-fleet.yaml --capabilities CAPABILITY_IAM &
done

wait
