#!/bin/bash

# Copyright (C) 2013 OpenStack Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.

# This script tests the checkout functions defined in functions.sh.

source functions.sh

LOCAL_AAR_VARS="TEST_GIT_CHECKOUTS TEST_ZUUL_REFS GIT_CLONE_AND_CD_ARG"

# Mock out the checkout function since the refs we're checking out do
# not exist.
function git_checkout {
    local project=$1
    local branch=$2

    project=`basename $project`
    if [[ "$branch" == "FETCH_HEAD" ]]; then
        branch=$FETCH_HEAD
    fi
    TEST_GIT_CHECKOUTS[$project]=$branch
}

# Mock out the fetch function since the refs we're fetching do not
# exist.
function git_fetch_at_ref {
    local project=$1
    local ref=$2

    project=`basename $project`
    if [ "$ref" != "" ]; then
        if [[ "${TEST_ZUUL_REFS[$project]}" =~ "$ref" ]]; then
            FETCH_HEAD="$ref"
            return 0
        fi
        return 1
    else
        # return failing
        return 1
    fi
}

# Mock out git repo functions so the git repos don't have to exist.
function git_has_branch {
    local project=$1
    local branch=$2

    case $branch in
        master) return 0 ;;
        stable/havana)
            case $project in
                openstack/glance) return 0 ;;
                openstack/swift) return 0 ;;
                openstack/nova) return 0 ;;
                openstack/keystone) return 0 ;;
                opestnack/tempest) return 0 ;;
            esac
    esac
    return 1
}

function git_prune {
    return 0
}

function git_remote_update {
    return 0
}

function git_remote_set_url {
    return 0
}

function git_clone_and_cd {
    if [[ "x${2}" == "x" ]]; then
        GIT_CLONE_AND_CD_ARG["ERROR"]="ERROR"
        return 1
    else
        GIT_CLONE_AND_CD_ARG[$2]="$1,$3"
    fi
    return 0
}

# Utility function for tests
function assert_equal {
    local lineno=`caller 0 | awk '{print $1}'`
    local function=`caller 0 | awk '{print $2}'`
    if [[ "$1" != "$2" ]]; then
        echo "ERROR: $1 != $2 in $function:L$lineno!"
        ERROR=1
    else
        echo "$function:L$lineno - ok"
    fi
}

function assert_raises {
    local lineno=`caller 0 | awk '{print $1}'`
    local function=`caller 0 | awk '{print $2}'`
    eval "$@" &>/dev/null
    if [[ $? -eq 0 ]]; then
        ERROR=1
        echo "ERROR: \`\`$@\`\` returned OK instead of error in $function:L$lineno!"
    fi
}

# Tests follow:
function test_one_on_master {
    # devstack-gate  master  ZA
    for aar_var in $LOCAL_AAR_VARS; do
        eval `echo "declare -A $aar_var"`
    done
    local ZUUL_PROJECT='openstack-infra/devstack-gate'
    local ZUUL_BRANCH='master'
    local ZUUL_REF='refs/zuul/master/ZA'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZA'

    setup_project openstack-infra/devstack-gate $ZUUL_BRANCH

    assert_equal "${TEST_GIT_CHECKOUTS[devstack-gate]}" 'refs/zuul/master/ZA'
}

function test_two_on_master {
    # devstack-gate  master  ZA
    # glance         master  ZB
    for aar_var in $LOCAL_AAR_VARS; do
        eval `echo "declare -A $aar_var"`
    done
    local ZUUL_PROJECT='openstack/glance'
    local ZUUL_BRANCH='master'
    local ZUUL_REF='refs/zuul/master/ZB'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZA'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZB'
    TEST_ZUUL_REFS[glance]+=' refs/zuul/master/ZB'

    setup_project openstack-infra/devstack-gate $ZUUL_BRANCH
    setup_project openstack/glance $ZUUL_BRANCH

    assert_equal "${TEST_GIT_CHECKOUTS[devstack-gate]}" 'refs/zuul/master/ZB'
    assert_equal "${TEST_GIT_CHECKOUTS[glance]}" 'refs/zuul/master/ZB'
}

function test_multi_branch_on_master {
    # devstack-gate        master         ZA
    # glance               stable/havana  ZB
    # python-glanceclient  master         ZC
    for aar_var in $LOCAL_AAR_VARS; do
        eval `echo "declare -A $aar_var"`
    done
    local ZUUL_PROJECT='openstack/python-glanceclient'
    local ZUUL_BRANCH='master'
    local ZUUL_REF='refs/zuul/master/ZC'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZA'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZB'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZC'
    TEST_ZUUL_REFS[glance]+=' refs/zuul/stable/havana/ZB'
    TEST_ZUUL_REFS[glance]+=' refs/zuul/stable/havana/ZC'
    TEST_ZUUL_REFS[python-glanceclient]+=' refs/zuul/master/ZC'

    setup_project openstack-infra/devstack-gate $ZUUL_BRANCH
    setup_project openstack/glance $ZUUL_BRANCH
    setup_project openstack/python-glanceclient $ZUUL_BRANCH

    assert_equal "${TEST_GIT_CHECKOUTS[devstack-gate]}" 'refs/zuul/master/ZC'
    assert_equal "${TEST_GIT_CHECKOUTS[glance]}" 'master'
    assert_equal "${TEST_GIT_CHECKOUTS[python-glanceclient]}" 'refs/zuul/master/ZC'
}

function test_multi_branch_project_override {
    # main branch is stable/havana
    # devstack-gate        master         ZA
    # devstack-gate        master         ZB
    # python-glanceclient  master         ZC
    # glance               stable/havana  ZD
    # tempest              not in queue (override to master)
    # oslo.config          not in queue (master because no stable/havana branch)
    # nova                 not in queue (stable/havana)
    for aar_var in $LOCAL_AAR_VARS; do
        eval `echo "declare -A $aar_var"`
    done
    local ZUUL_PROJECT='openstack/glance'
    local ZUUL_BRANCH='stable/havana'
    local OVERRIDE_TEMPEST_PROJECT_BRANCH='master'
    local ZUUL_REF='refs/zuul/stable/havana/ZD'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZA'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZB'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZC'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZD'
    TEST_ZUUL_REFS[python-glanceclient]+=' refs/zuul/master/ZC'
    TEST_ZUUL_REFS[python-glanceclient]+=' refs/zuul/master/ZD'
    TEST_ZUUL_REFS[glance]+=' refs/zuul/stable/havana/ZD'

    setup_project openstack-infra/devstack-gate $ZUUL_BRANCH
    setup_project openstack/glance $ZUUL_BRANCH
    setup_project openstack/python-glanceclient $ZUUL_BRANCH
    setup_project openstack/tempest $ZUUL_BRANCH
    setup_project openstack/nova $ZUUL_BRANCH
    setup_project openstack/oslo.config $ZUUL_BRANCH

    assert_equal "${TEST_GIT_CHECKOUTS[devstack-gate]}" 'refs/zuul/master/ZD'
    assert_equal "${TEST_GIT_CHECKOUTS[glance]}" 'refs/zuul/stable/havana/ZD'
    assert_equal "${TEST_GIT_CHECKOUTS[tempest]}" 'master'
    assert_equal "${TEST_GIT_CHECKOUTS[nova]}" 'stable/havana'
    assert_equal "${TEST_GIT_CHECKOUTS[oslo.config]}" 'master'
    assert_equal "${TEST_GIT_CHECKOUTS[python-glanceclient]}" 'refs/zuul/master/ZD'
}

function test_multi_branch_on_stable {
    # devstack-gate        master         ZA
    # glance               stable/havana  ZB
    # python-glanceclient not in queue
    for aar_var in $LOCAL_AAR_VARS; do
        eval `echo "declare -A $aar_var"`
    done
    local ZUUL_PROJECT='openstack/glance'
    local ZUUL_BRANCH='stable/havana'
    local ZUUL_REF='refs/zuul/stable/havana/ZB'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZA'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZB'
    TEST_ZUUL_REFS[glance]+=' refs/zuul/stable/havana/ZB'

    setup_project openstack-infra/devstack-gate $ZUUL_BRANCH
    setup_project openstack/glance $ZUUL_BRANCH
    setup_project openstack/python-glanceclient $ZUUL_BRANCH

    assert_equal "${TEST_GIT_CHECKOUTS[devstack-gate]}" 'refs/zuul/master/ZB'
    assert_equal "${TEST_GIT_CHECKOUTS[glance]}" 'refs/zuul/stable/havana/ZB'
    assert_equal "${TEST_GIT_CHECKOUTS[python-glanceclient]}" 'master'
}

function test_multi_git_base_project_override {
    # osrg/ryu              https://github.com
    # test/devstack-gate    https://foo.bar.com
    # openstack/keystone    https://git.openstack.org
    # openstack/glance      http://tarballs.openstack.org
    for aar_var in $LOCAL_AAR_VARS; do
        eval `echo "declare -A $aar_var"`
    done
    GIT_CLONE_AND_CD_ARG["ERROR"]="NULL"
    local ZUUL_PROJECT='openstack/neutron'
    local ZUUL_BRANCH='master'
    local ZUUL_REF='refs/zuul/master/ZA'
    local GIT_BASE=""
    local GIT_BASE_DEF="https://git.openstack.org"

    local OVERRIDE_RYU_GIT_BASE='https://github.com'
    setup_project "osrg/ryu" $ZUUL_BRANCH
    local OVERRIDE_DEVSTACK_GATE_GIT_BASE='https://foo.bar.com'
    setup_project "test/devstack-gate" $ZUUL_BRANCH
    setup_project "openstack/keystone" $ZUUL_BRANCH
    local GIT_BASE="http://tarballs.openstack.org"
    setup_project "openstack/glance" $ZUUL_BRANCH

    assert_equal "${GIT_CLONE_AND_CD_ARG["ryu"]}" "osrg/ryu,$OVERRIDE_RYU_GIT_BASE"
    assert_equal "${GIT_CLONE_AND_CD_ARG["devstack-gate"]}" "test/devstack-gate,$OVERRIDE_DEVSTACK_GATE_GIT_BASE"
    assert_equal "${GIT_CLONE_AND_CD_ARG["keystone"]}" "openstack/keystone,$GIT_BASE_DEF"
    assert_equal "${GIT_CLONE_AND_CD_ARG["glance"]}" "openstack/glance,$GIT_BASE"
    assert_equal "${GIT_CLONE_AND_CD_ARG["ERROR"]}" "NULL"
}

function test_grenade_backward {
    # devstack-gate        master         ZA
    # nova                 stable/havana  ZB
    # keystone             stable/havana  ZC
    # keystone             master         ZD
    # glance               master         ZE
    # swift not in queue
    # python-glanceclient not in queue
    # havana -> master (with changes)

    for aar_var in $LOCAL_AAR_VARS; do
        eval `echo "declare -A $aar_var"`
    done
    local ZUUL_PROJECT='openstack/glance'
    local ZUUL_BRANCH='master'
    local ZUUL_REF='refs/zuul/master/ZE'
    local GRENADE_OLD_BRANCH='stable/havana'
    local GRENADE_NEW_BRANCH='master'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZA'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZB'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZC'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZD'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZE'
    TEST_ZUUL_REFS[nova]+=' refs/zuul/stable/havana/ZB'
    TEST_ZUUL_REFS[nova]+=' refs/zuul/stable/havana/ZC'
    TEST_ZUUL_REFS[nova]+=' refs/zuul/stable/havana/ZD'
    TEST_ZUUL_REFS[nova]+=' refs/zuul/stable/havana/ZE'
    TEST_ZUUL_REFS[keystone]+=' refs/zuul/stable/havana/ZC'
    TEST_ZUUL_REFS[keystone]+=' refs/zuul/stable/havana/ZD'
    TEST_ZUUL_REFS[keystone]+=' refs/zuul/stable/havana/ZE'
    TEST_ZUUL_REFS[keystone]+=' refs/zuul/master/ZD'
    TEST_ZUUL_REFS[keystone]+=' refs/zuul/master/ZE'
    TEST_ZUUL_REFS[glance]+=' refs/zuul/master/ZE'

    setup_project openstack-infra/devstack-gate $GRENADE_OLD_BRANCH
    setup_project openstack/nova $GRENADE_OLD_BRANCH
    setup_project openstack/keystone $GRENADE_OLD_BRANCH
    setup_project openstack/glance $GRENADE_OLD_BRANCH
    setup_project openstack/swift $GRENADE_OLD_BRANCH
    setup_project openstack/python-glanceclient $GRENADE_OLD_BRANCH

    assert_equal "${TEST_GIT_CHECKOUTS[devstack-gate]}" 'refs/zuul/master/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[nova]}" 'refs/zuul/stable/havana/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[keystone]}" 'refs/zuul/stable/havana/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[glance]}" 'stable/havana'
    assert_equal "${TEST_GIT_CHECKOUTS[swift]}" 'stable/havana'
    assert_equal "${TEST_GIT_CHECKOUTS[python-glanceclient]}" 'master'

    declare -A TEST_GIT_CHECKOUTS

    setup_project openstack-infra/devstack-gate $GRENADE_NEW_BRANCH
    setup_project openstack/nova $GRENADE_NEW_BRANCH
    setup_project openstack/keystone $GRENADE_NEW_BRANCH
    setup_project openstack/glance $GRENADE_NEW_BRANCH
    setup_project openstack/swift $GRENADE_NEW_BRANCH
    setup_project openstack/python-glanceclient $GRENADE_NEW_BRANCH

    assert_equal "${TEST_GIT_CHECKOUTS[devstack-gate]}" 'refs/zuul/master/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[nova]}" 'master'
    assert_equal "${TEST_GIT_CHECKOUTS[keystone]}" 'refs/zuul/master/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[glance]}" 'refs/zuul/master/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[swift]}" 'master'
    assert_equal "${TEST_GIT_CHECKOUTS[python-glanceclient]}" 'master'
}

function test_grenade_forward {
    # devstack-gate        master         ZA
    # nova                 master         ZB
    # keystone             stable/havana  ZC
    # keystone             master         ZD
    # glance               stable/havana  ZE
    # swift not in queue
    # python-glanceclient not in queue
    # havana (with changes) -> master

    for aar_var in $LOCAL_AAR_VARS; do
        eval `echo "declare -A $aar_var"`
    done
    local ZUUL_PROJECT='openstack/glance'
    local ZUUL_BRANCH='stable/havana'
    local ZUUL_REF='refs/zuul/stable/havana/ZE'
    local GRENADE_OLD_BRANCH='stable/havana'
    local GRENADE_NEW_BRANCH='master'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZA'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZB'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZC'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZD'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZE'
    TEST_ZUUL_REFS[nova]+=' refs/zuul/master/ZB'
    TEST_ZUUL_REFS[nova]+=' refs/zuul/master/ZC'
    TEST_ZUUL_REFS[nova]+=' refs/zuul/master/ZD'
    TEST_ZUUL_REFS[nova]+=' refs/zuul/master/ZE'
    TEST_ZUUL_REFS[keystone]+=' refs/zuul/stable/havana/ZC'
    TEST_ZUUL_REFS[keystone]+=' refs/zuul/stable/havana/ZD'
    TEST_ZUUL_REFS[keystone]+=' refs/zuul/stable/havana/ZE'
    TEST_ZUUL_REFS[keystone]+=' refs/zuul/master/ZD'
    TEST_ZUUL_REFS[keystone]+=' refs/zuul/master/ZE'
    TEST_ZUUL_REFS[glance]+=' refs/zuul/stable/havana/ZE'

    setup_project openstack-infra/devstack-gate $GRENADE_OLD_BRANCH
    setup_project openstack/nova $GRENADE_OLD_BRANCH
    setup_project openstack/keystone $GRENADE_OLD_BRANCH
    setup_project openstack/glance $GRENADE_OLD_BRANCH
    setup_project openstack/swift $GRENADE_OLD_BRANCH
    setup_project openstack/python-glanceclient $GRENADE_OLD_BRANCH

    assert_equal "${TEST_GIT_CHECKOUTS[devstack-gate]}" 'refs/zuul/master/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[nova]}" 'stable/havana'
    assert_equal "${TEST_GIT_CHECKOUTS[keystone]}" 'refs/zuul/stable/havana/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[glance]}" 'refs/zuul/stable/havana/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[swift]}" 'stable/havana'
    assert_equal "${TEST_GIT_CHECKOUTS[python-glanceclient]}" 'master'

    declare -A TEST_GIT_CHECKOUTS

    setup_project openstack-infra/devstack-gate $GRENADE_NEW_BRANCH
    setup_project openstack/nova $GRENADE_NEW_BRANCH
    setup_project openstack/keystone $GRENADE_NEW_BRANCH
    setup_project openstack/glance $GRENADE_NEW_BRANCH
    setup_project openstack/swift $GRENADE_NEW_BRANCH
    setup_project openstack/python-glanceclient $GRENADE_NEW_BRANCH

    assert_equal "${TEST_GIT_CHECKOUTS[devstack-gate]}" 'refs/zuul/master/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[nova]}" 'refs/zuul/master/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[keystone]}" 'refs/zuul/master/ZE'
    assert_equal "${TEST_GIT_CHECKOUTS[glance]}" 'master'
    assert_equal "${TEST_GIT_CHECKOUTS[swift]}" 'master'
    assert_equal "${TEST_GIT_CHECKOUTS[python-glanceclient]}" 'master'
}

function test_branch_override {
    # glance               stable/havana  ZA
    # devstack-gate        master         ZB
    # swift not in queue
    # python-glanceclient not in queue

    for aar_var in $LOCAL_AAR_VARS; do
        eval `echo "declare -A $aar_var"`
    done
    local ZUUL_PROJECT='openstack-infra/devstack-gate'
    local ZUUL_BRANCH='master'
    local ZUUL_REF='refs/zuul/master/ZB'
    local OVERRIDE_ZUUL_BRANCH='stable/havana'
    TEST_ZUUL_REFS[devstack-gate]+=' refs/zuul/master/ZB'
    TEST_ZUUL_REFS[glance]+=' refs/zuul/stable/havana/ZA'
    TEST_ZUUL_REFS[glance]+=' refs/zuul/stable/havana/ZB'

    setup_project openstack-infra/devstack-gate $OVERRIDE_ZUUL_BRANCH
    setup_project openstack/glance $OVERRIDE_ZUUL_BRANCH
    setup_project openstack/swift $OVERRIDE_ZUUL_BRANCH
    setup_project openstack/python-glanceclient $OVERRIDE_ZUUL_BRANCH

    assert_equal "${TEST_GIT_CHECKOUTS[devstack-gate]}" 'refs/zuul/master/ZB'
    assert_equal "${TEST_GIT_CHECKOUTS[glance]}" 'refs/zuul/stable/havana/ZB'
    assert_equal "${TEST_GIT_CHECKOUTS[swift]}" 'stable/havana'
    assert_equal "${TEST_GIT_CHECKOUTS[python-glanceclient]}" 'master'
}

function test_periodic {
    # No queue

    for aar_var in $LOCAL_AAR_VARS; do
        eval `echo "declare -A $aar_var"`
    done
    local ZUUL_BRANCH='stable/havana'
    local ZUUL_PROJECT='openstack/glance'

    setup_project openstack/glance $ZUUL_BRANCH

    assert_equal "${TEST_GIT_CHECKOUTS[glance]}" 'stable/havana'
}

# setup_workspace fails without argument
function test_workspace_branch_arg {
    assert_raises setup_workspace
}

# Run tests:
#set -o xtrace
test_branch_override
test_grenade_backward
test_grenade_forward
test_multi_branch_on_master
test_multi_branch_on_stable
test_multi_branch_project_override
test_multi_git_base_project_override
test_one_on_master
test_periodic
test_two_on_master
test_workspace_branch_arg

if [[ ! -z "$ERROR" ]]; then
    echo
    echo "FAIL: Tests have errors! See output above."
    echo
    exit 1
else
    echo
    echo "Tests completed successfully!"
    echo
fi
