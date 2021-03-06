#!/bin/bash

#==============================================================================
#               NAME:  dti_preprocessing.sh
#
#        DESCRIPTION:  This script takes an input directory that must contain
#                      dti.nii.gz, bvals and bvecs_orig, and then runs  
#                      eddy current correction, rotate bvecs, brain extraction,
#                      dtifit, bedpostX and tbss 1 and 2.
#
#              USAGE:  dti_preprocessing.sh <dti_data_folder> <sub_id> <bedpost_option>
#                           eg: dti_preprocessing.sh ${dti_dir} ${sub_id} ${bedpost_option}
#                           eg: dti_preprocessing.sh /home/kw401/MRIMPACT/ANALYSES/1106/t1/DTI 1106t1 no
#
#        PARAMETER 1:  DTI data folder (full path)
#                           If you're using this script as part of another
#                               eg: ${dti_dir}
#                           If you're using this script alone
#                               eg: /home/kw401/MRIMPACT/ANALYSES/1106/t1/DTI 
#
#        PARAMETER 2:  sub_id
#                           eg: ${subid}
#                           eg: 1106t1
#
#        PARAMETER 3:  bedpost_option
#                      Because bedpostx takes so long it might be better to skip it.
#                      This it can be either yes or no. Capitalization doesn't matter.
#                           eg: ${bedpost_option}
#                           eg: no
#
#             AUTHOR:  Kirstie Whitaker
#                          kw401@cam.ac.uk
#
#            CREATED:  19th February 2013
#==============================================================================

#------------------------------------------------------------------------------
# Define usage function
function usage {
    echo "USAGE:"
    echo "dti_preprocessing.sh <dti_data_folder> <sub_id> <bedpost_option>"
    echo "    eg: dti_preprocessing.sh \${dti_dir} \${sub_id} \${bedpost_option}"
    echo "    eg: dti_preprocessing.sh /home/kw401/MRIMPACT/ANALYSES/1106/t1/DTI 1106t1 no"
    exit
}
#------------------------------------------------------------------------------
 
#------------------------------------------------------------------------------
# Assign arguments
dir=$1
if [[ ! -d /${dir} ]]; then
    dir=`pwd`/${dir}
fi
sub=$2

# make bedpost_option all lower case so capitalision doesn't matter
bedpost_option=`echo ${3} | tr '[:upper:]' '[:lower:]'`

#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Check inputs

### Step 1: check arguments
# Exit if dti directory doesn't exist
if [[ ! -d ${dir} ]]; then
    echo "    No DTI directory"
    print_usage=1
fi

# Exit if subID is an empty string
if [[ -z ${sub} ]]; then
    echo "    SubID is blank"
    print_usage=1
fi

# Exit if the bedpost_option is neither yes nor no
if [[ ${bedpost_option} != "yes" && ${bedpost_option} != "no" ]]; then
    echo "    Bedpost option not recognised"
    echo "    bedpost_option = ${bedpost_option}"
    print_usage=1
fi

# Print the usage if necessary
if [[ ${print_usage} == 1 ]]; then
    usage
fi

### Step 2: Check data
# Make sure dti.nii.gz, bvals and bvecs_orig files exist
if [[ ! -f ${dir}/dti.nii.gz ]]; then
    if [[ -f ${dir}/dti.nii ]]; then
        gzip ${dir}/dti.nii
    else
        echo "    No dti.nii.gz file"
        print_usage=1
    fi
fi
if [[ ! -f ${dir}/bvals ]]; then
    echo "    No bvals file"
    print_usage=1
fi
if [[ ! -f ${dir}/bvecs_orig ]]; then
    echo "    No bvecs_orig file"
    print_usage=1
fi

# Print the usage if necessary
if [[ ${print_usage} == 1 ]]; then
    usage
fi
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Set up the rot_bvecs_script

# If you're Kirstie, then you're fine
# First try the bcni:
rot_bvecs_script=(./SCRIPTS/DTI_PROCESSING-master/fdt_rotate_bvecs.sh)

if [[ ! -w ${rot_bvecs_script} ]]; then
    # Then try the cbu:
    rot_bvecs_script=(./SCRIPTS/DTI_PROCESSING-master/fdt_rotate_bvecs.sh)
    # And if it's not in either of those places
    if [[ ! -f ${rot_bvecs_script} ]]; then
        # Find out where this script is saved, and download the fdt_rotate_bvecs.sh
        # script into the same folder:
        scripts_dir="$( cd "$( dirname "$0" )" && pwd )"
        # (Handily stolen from http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in)

        rot_bvecs_script=${scripts_dir}/fdt_rotate_bvecs.sh

        wget -O ${rot_bvecs_script} https://raw.github.com/HappyPenguin/FSL_COMMUNITY_CODE/master/fdt_rotate_bvecs.sh --no-check-certificate
    fi
fi

# Make that script executable
chmod +x ${rot_bvecs_script}

# And make sure that it's in unix form
dos2unix ${rot_bvecs_script} > /dev/null
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Get started
echo "DIR: ${dir}"
echo "SUBID: ${sub}"

# Make the LOGS dir
logdir=${dir}/LOGS
mkdir -p ${logdir}


#------------------------------------------------------------------------------
# Eddy correct to the first volume
if [[ ! -f ${dir}/dti_ec.nii.gz ]]; then
    echo "    Starting eddy correction step"
    rm -f ${dir}/dti_ec.ecclog
    eddy_correct ${dir}/dti.nii.gz ${dir}/dti_ec.nii.gz 0 \
            > ${logdir}/eddycorrect 2> ${logdir}/errors_eddycorrect
else
    echo "    Eddy correction step already completed"
fi

#------------------------------------------------------------------------------
# Rotate bvecs

if [[ ! -f ${dir}/bvecs ]]; then
    echo "    Rotating bvecs"
    ${rot_bvecs_script} ${dir}/bvecs_orig ${dir}/bvecs \
        ${dir}/dti_ec.ecclog >> ${logdir}/eddycorrect 2> ${logdir}/errors_eddycorrect
else
    echo "    Bvecs already rotated"
fi

#------------------------------------------------------------------------------
# Brain extract
if [[ ! -f ${dir}/dti_ec.nii.gz ]]; then
    echo "    ERROR: Can't brain extract because eddy_correct has not been completed"
    echo "    EXITING"
    exit

elif [[ ! -f ${dir}/dti_ec_brain.nii.gz ]]; then
    echo "    Brain extracting"
    bet ${dir}/dti_ec.nii.gz ${dir}/dti_ec_brain.nii.gz \
            -f 0.15 -m > ${logdir}/bet 2> ${logdir}/errors_bet

else
    echo "    Brain already extracted"
fi

#------------------------------------------------------------------------------
# DTIfit (FDT)
if [[ ! -f ${dir}/dti_ec_brain_mask.nii.gz || ! -f ${dir}/bvecs ]]; then
    echo "    ERROR: Can't fit tensor because brain extraction has not been completed"
    echo "    EXITING"
    exit

elif [[ ! -f ${dir}/bvecs ]]; then
    echo "    ERROR: Can't fit tensor because bvecs file doesn't exist"
    echo "    EXITING"
    exit

elif [[ ! -f ${dir}/FDT/${sub}_sse.nii.gz ]]; then
    echo "    Fitting tensor"
    mkdir -p ${dir}/FDT
    dtifit -k ${dir}/dti_ec.nii.gz \
        -m ${dir}/dti_ec_brain_mask.nii.gz \
        -r ${dir}/bvecs \
        -b ${dir}/bvals \
        --sse \
        --save_tensor \
        -o ${dir}/FDT/${sub} \
        > ${logdir}/dtifit 2> ${logdir}/errors_dtifit
    
    # Add L2 and L3 together and divide by two to create a measure of
    # radial (perpendicular) diffusivity
    fslmaths ${dir}/FDT/${sub}_L2.nii.gz -add ${dir}/FDT/${sub}_L3.nii.gz -div 2 \
        ${dir}/FDT/${sub}_L23.nii.gz

else
   echo "    Tensor already fit"
fi

#------------------------------------------------------------------------------
# BedpostX
if [[ ! -f ${dir}/BEDPOSTX/data.nii.gz ]]; then
    echo "    Setting up bedpostX directory"
    mkdir -p ${dir}/BEDPOSTX
    cp ${dir}/bvals ${dir}/BEDPOSTX/
    cp ${dir}/bvecs ${dir}/BEDPOSTX/
    cp ${dir}/dti_ec_brain_mask.nii.gz \
    ${dir}/BEDPOSTX/nodif_brain_mask.nii.gz
    cp ${dir}/dti_ec.nii.gz ${dir}/BEDPOSTX/data.nii.gz
    
    # Only actually *run* bedpostx if the bedpost_option is "yes"
    if [[ ! -f ${dir}/BEDPOSTX.bedpostX/dyads2.nii.gz && ${bedpost_option} == "yes" ]]; then
        echo "    Running bedpostX"
        bedpostx_gpu ${dir}/BEDPOSTX/ > ${logdir}/bedpostx 2> ${logdir}/errors_bedpostx
    fi
    
else
    echo "    bedpostX already complete"
fi

#------------------------------------------------------------------------------
# TBSS 1 and 2
if [[ ! -f ${dir}/FDT/${sub}_FA.nii.gz ]]; then
    echo "    ERROR: Can't run TBSS as tensor has not been fit"
    echo "    EXITING"
    exit

elif [[ ! -f ${dir}/TBSS/FA/reverse_fnirt_warp.nii.gz ]]; then
    echo "    Now starting tbss"
    if [[ ! -f ${dir}/TBSS/FA/${sub}_FA_FA_to_target_warp.nii.gz ]]; then
        echo "    Running TBSS"
        rm -rf ${dir}/TBSS
        mkdir -p ${dir}/TBSS
        cp ${dir}/FDT/*FA* ${dir}/TBSS/
        # Re-orientate the FA map to standard space
        # note that you aren't resampling, just spinning it around a bit.
        fslreorient2std ${dir}/TBSS/${sub}_FA.nii.gz ${dir}/TBSS/${sub}_FA.nii.gz

        cd ${dir}/TBSS/
        tbss_1_preproc * > ${logdir}/tbss 2> ${logdir}/errors_tbss
        tbss_2_reg -T >> ${logdir}/tbss 2>> ${logdir}/errors_tbss
    fi 
    # Now create the inverse fnirt warp
    echo "    Inverting FNIRT warp"
    if [[ -d ${dir}/TBSS/FA && \
           ! -f ${dir}/TBSS/FA/reverse_fnirt_warp.nii.gz ]]; then
        invwarp -r ${dir}/TBSS/FA/${sub}_FA_FA.nii.gz \
                -w ${dir}/TBSS/FA/${sub}_FA_FA_to_target_warp.nii.gz \
                -o ${dir}/TBSS/FA/reverse_fnirt_warp.nii.gz
    fi
else
    echo "    TBSS already complete"
fi

#------------------------------------------------------------------------------
# And you're done!
echo "--------------------------------"
#------------------------------------------------------------------------------

