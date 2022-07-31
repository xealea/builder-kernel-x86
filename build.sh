#! /bin/bash
# shellcheck disable=SC2154

 # Script For Building Linux x86_64 Kernel
 #
 # Copyright (c) 2022-2024 vcyzteen <vcyzteen@pm.me>
 #
 # Licensed under the Apache License, Version 2.0 (the "License");
 # you may not use this file except in compliance with the License.
 # You may obtain a copy of the License at
 #
 #      http://www.apache.org/licenses/LICENSE-2.0
 #
 # Unless required by applicable law or agreed to in writing, software
 # distributed under the License is distributed on an "AS IS" BASIS,
 # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 # See the License for the specific language governing permissions and
 # limitations under the License.
 #

# x86_64 kernel builder

# Bail out if script fails
set -e

# Function to show an informational message
msg() {
	echo
	echo -e "\e[1;32m$*\e[0m"
	echo
}

err() {
	echo -e "\e[1;41m$*\e[0m"
	exit 1
}

cdir() {
	cd "$1" 2>/dev/null || \
		err "The directory $1 doesn't exists !"
}


# The defult directory where the kernel should be placed
KERNEL_DIR="$(pwd)"
BASEDIR="$(basename "$KERNEL_DIR")"
DISTRO=$(source /etc/os-release && echo "${NAME}")

# Architecture
ARCH=x86
SUBARCH=$ARCH

# User builder
KBUILD_BUILD_USER=vcyzteen

# Host builder
KBUILD_BUILD_HOST=xea@linux

# The defconfig which should be used. Get it from config.gz from
# your device or check source
DEFCONFIG=xea_defconfig

# Specify compiler. 
# 'clang' or 'gcc'
COMPILER=gcc

# Push ZIP to Telegram. 1 is YES | 0 is NO(default)
PTTG=1
	if [ $PTTG = 1 ]
	then
		# Set Telegram Chat ID
		CHATID="-1001721818658"
	fi

# Files/artifacts
FILES="*.deb"

#Check Kernel Version
KERVER=$(make kernelversion)

# Set Date 
DATE=$(TZ=Asia/Jakarta date +"%Y%m%d-%T")

export() {
    if [ $COMPILER = "clang" ]
	then
		KBUILD_COMPILER_STRING=$(/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
		PATH=/bin/:$PATH
	elif [ $COMPILER = "gcc" ]
	then
		KBUILD_COMPILER_STRING=$(/bin/gcc  --version | head -n 1)
		PATH=/bin/:/bin/:/usr/bin:$PATH
	fi

    BOT_MSG_URL="https://api.telegram.org/bot$token/sendMessage"
	BOT_BUILD_URL="https://api.telegram.org/bot$token/sendDocument"
	PROCS=$(nproc --all)

    export KBUILD_BUILD_USER ARCH SUBARCH \
	BOT_MSG_URL BOT_BUILD_URL PROCS
}


tg_post_msg() {
	curl -s -X POST "$BOT_MSG_URL" -d chat_id="$CHATID" \
	-d "disable_web_page_preview=true" \
	-d "parse_mode=html" \
	-d text="$1"

}

tg_post_build() {
	#Post MD5Checksum alongwith for easeness
	MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)

	#Show the Checksum alongwith caption
	curl --progress-bar -F document=@"$1" "$BOT_BUILD_URL" \
	-F chat_id="$CHATID"  \
	-F "disable_web_page_preview=true" \
	-F "parse_mode=Markdown" \
	-F caption="$2 | *MD5 Checksum : *\`$MD5CHECK\`"
}

build_kernel() {
	if [ $INCREMENTAL = 0 ]
	then
		msg "|| Cleaning Sources ||"
		make mrproper && rm -rf out
	fi

	if [ "$PTTG" = 1 ]
 	then
		tg_post_msg "<b>$KBUILD_BUILD_VERSION CI Build Triggered</b>%0A<b>Docker OS: </b><code>$DISTRO</code>%0A<b>Kernel Version : </b><code>$KERVER</code>%0A<b>Date : </b><code>$(TZ=Asia/Jakarta date)</code>%0A<b>Pipeline Host : </b><code>$KBUILD_BUILD_HOST</code>%0A<b>Host Core Count : </b><code>$PROCS</code>%0A<b>Compiler Used : </b><code>$KBUILD_COMPILER_STRING</code>"
	fi

	make O=out oldconfig

	BUILD_START=$(date +"%s")
	
	if [ $COMPILER = "clang" ]
	then
		MAKE+=(
            CC=gcc
		)
	elif [ $COMPILER = "gcc" ]
	then
		MAKE+=(
            CC=clang
		)
	fi
	
	if [ $SILENCE = "1" ]
	then
		MAKE+=( -s )
	fi

	msg "|| Started Compilation ||"
	make -kj"$PROCS" O=out bindeb-pkg \
		V=$VERBOSE \
		"${MAKE[@]}" 2>&1 | tee error.log

		BUILD_END=$(date +"%s")
		DIFF=$((BUILD_END - BUILD_START))

		if [ -f "$KERNEL_DIR"/out/../$FILES ]
		then
			msg "|| Kernel successfully compiled ||"
        else
			if [ "$PTTG" = 1 ]
 			then
				tg_post_build "error.log" "*Build failed to compile after $((DIFF / 60)) minute(s) and $((DIFF % 60)) seconds*"
			fi
		fi
}

kernel_wrapit() {
    if [ "$PTTG" = 1 ]
 	    then
		    tg_post_build "$FILES" "Build took : $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)"
	fi
	cd ..
}
exports
build_kernel
kernel_wrapit

####