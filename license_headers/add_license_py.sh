#!/bin/bash

YYYY='2014'
COMPANY='MyCompany'
EMAIL='info@mycompany.com'
WEBSITE='http://www.mycompany.com'
PROJECT='MyProject'
coding='#coding=utf-8'
copyright="################################################################################
# <copyright>
# Copyright (c) $YYYY $COMPANY and/or its affiliates. All rights reserved.
#
# Email: $EMAIL
# Web site: $WEBSITE
# </copyright>
#
# <description>
# This file is part of $PROJECT.
# </description>
#
# <license>
# The methods and techniques described herein are considered trade secrets
# and/or confidential. Reproduction, distribution and/or modification in whole
# or in part, is forbidden except by express written permission of $COMPANY.
# 
# THIS CODE AND INFORMATION ARE PROVIDED 'AS IS' WITHOUT WARRANTY OF ANY         
# KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE            
# IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. 
# </license>                                                                     
#################################################################################
"

files=`find . -type f | grep .py$`
for f in $files; do
    echo $f
    if [ -z "`grep '<copyright>' $f`" ]
    then
        echo "+++++++++++++++++++++++++++++++++++++++"
        headers=`head -n2 $f | grep -e ^#! -e coding`
        sed -n '
        s/^#!.\+$/\n/
        s/^#coding.\+$/\n/
        s/^# \-\*\- coding.\+$/\n/
        p' $f > $f.tmp
        echo "$headers" > $f
        echo "$copyright" >> $f
        cat $f.tmp >> $f
        rm $f.tmp
    fi
done

