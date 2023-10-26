#!/usr/bin/env sh

# state variables
: "${__is_submenu:=0}" "${__is_fzf_preview:=0}"

# versioning system:
# major.minor.bugs
YTFZF_VERSION="2.6.1"

#ENVIRONMENT VARIABLES {{{
: "${YTFZF_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/ytfzf}"
: "${YTFZF_CONFIG_FILE:=$YTFZF_CONFIG_DIR/conf.sh}"
: "${YTFZF_SUBSCRIPTIONS_FILE:=$YTFZF_CONFIG_DIR/subscriptions}"
: "${YTFZF_THUMBNAIL_VIEWERS_DIR:=$YTFZF_CONFIG_DIR/thumbnail-viewers}"
: "${YTFZF_SORT_NAMES_DIR:=$YTFZF_CONFIG_DIR/sort-names}"
: "${YTFZF_CUSTOM_INTERFACES_DIR:=$YTFZF_CONFIG_DIR/interfaces}"
: "${YTFZF_URL_HANDLERS_DIR:=$YTFZF_CONFIG_DIR/url-handlers}"
: "${YTFZF_CUSTOM_THUMBNAILS_DIR:=$YTFZF_CONFIG_DIR/thumbnails}"
: "${YTFZF_EXTENSIONS_DIR:=$YTFZF_CONFIG_DIR/extensions}"
: "${YTFZF_CUSTOM_SCRAPERS_DIR:=$YTFZF_CONFIG_DIR/scrapers}"

: "${YTFZF_SYSTEM_ADDON_DIR:=/usr/local/share/ytfzf/addons}"

: "${YTFZF_TEMP_DIR:="${TMPDIR:-/tmp}"/ytfzf-$(id -u)}"

: "${YTFZF_LOGFILE:=}"

if [ "$YTFZF_LOGFILE" ] && { [ "$__is_fzf_preview" -eq 1 ] || [ "$__is_submenu" -eq 1 ]; }; then
    printf "[%s]\n==============\nSubmenu: %d\nFzf Preview: %d\n==============\n" "$(date)" "$__is_submenu" "$__is_fzf_preview" >> "${YTFZF_LOGFILE}"
elif [ "${YTFZF_LOGFILE}" ]; then
    : > "${YTFZF_LOGFILE}"
fi

! [ -d "$YTFZF_TEMP_DIR" ] && mkdir -p "${YTFZF_TEMP_DIR}"

export YTFZF_PID=$$
#}}}

############################
#        DEBUGGING         #
############################

# There are only a couple tooling methods that I know of for debugging (other than printing stuff everywhere)
# set log_level to 3, and set YTFZF_LOGFILE=./some-file.log
# set -x may also be used.

############################
#        CODE STYLE        #
############################

##################
# VARIABLE NAMES #
##################

# Starts with __ if it is a state variable thatt is allowed to be accessed globally.
# for example: __is_submenu is a state variable that keeps track of whether or not itt is a submenu
# another example: __scrape_count is the current scrape number

# Environment variables should be all caps, do not use full caps for constansts

# Const variable should start with c_ or const_

# Configuration variables should not start with any prefix, and should have a --long-opt equivelent with as close of a name as posisble to the variable
# example: the search_source variable has the long opt equivelent of --search-source

# Private variables should start with an _
# A major exception to this is the _search variable, which is global, and should not be used as a local variable.

##################
# FUNCTION NAMES #
##################

# Private functions should start with an _

# All other functions that should be accessed globally should not start with an _
# A major exception to this is _get_request which is a global function

# interface functions MUST start with interface_ in order to work properly
# scraper functions MUST start with scrape_ in order to work properly

############################
#          ERRORS          #
############################

# 0: success
# 1: general error
# 2: invalid -opt or command argument, invalid argument for opt, configuration error
# eg: ytfzf -c terminal (invalid scrape)
# 3: missing dependency
# 4: scraping error
# 5: empty search
# *: Likely a curl error

############################
#          CODE            #
############################

# colors {{{
c_red="\033[1;31m"
c_green="\033[1;32m"
c_yellow="\033[1;33m"
c_blue="\033[1;34m"
c_magenta="\033[1;35m"
c_cyan="\033[1;36m"
c_reset="\033[0m"
c_bold="\033[1m"
#}}}

: "${check_vars_exists:=${YTFZF_CHECK_VARS_EXISTS:-1}}"

# __ytfzf__ extension {{{

print_help___ytfzf__() {
	#the [2A will clear the \n---__ytfzf__--- garbage (in supported terminals)
	printf "\033[2A%s" \
		"Usage: ytfzf [OPTIONS...] <search-query>
    The search-query can also be read from stdin
    GENERAL OPTIONS:
        -h                      Show this help text

        --version                Get the current version

        --version-all            Get the current version of ytfzf,
                                    and required dependencies

    UTILITY OPTIONS:
        --channel-link=<link>    Gets the uuid of a youtube channel from a link.

    PLAYING OPTIONS:
        -d                      Download the selected video(s)

        -m                      Only play audio

        -f                      Select a video format before playing

        --format-selection=<type>
                                Type can either be normal, or simple
        --format-sort=<sort>    The sort used in ytdl for -f.

        --video-pref=<pref>     The ytdl video preference.

        --audio-pref=<pref>     The ytdl audio preference.

        --ytdl-pref=<pref>      The combined ytdl video and audio preference.

        -u <url handler>        The program to use for handling urls
                                    (deafult: multimedia_player)
        -L                      Show the link of selected video(s)

        -I <info>               Instead of playing the selected video(s),
                                    get information about them.
                                    Options can be separated with a comma,
                                      eg: L,R
                                    Options for info:
                                      L:         print the link of the video
                                      VJ:        print the json of the video
                                      J:         print the json of all videos
                                                 shown in the search
                                      R:         print the data
                                                 of the selected videos,
                                                 as appears in the menu
                                      F:         print the selected video format
        --info-wait              When -I or -L is used,
                                 wait for user input before continuing

        --info-action=<action>   
                                 The action to do when --info-wait is 1.
                                 action can be one of
                                      q: exit
                                      Q: exit (bypass -l)
                                      '': play video

        --detach                 Detach the url handler from the terminal

        --notify-playing         Sends a notification when a video is selected.

        --url-handler-opts=<opts>
                                 Pass the given opts to the url handler.

        --ytdl-opts=<opts>       Pass the opts to ytdl when downloading

        --ytdl-path=<path>       The path to youtube-dl

    MENU OPTIONS:
        -l                      Reopen the menu when the video stops playing

        -t                      Show thumbnails

        -T <viewer>             The program to use for displaying thumbnails.
                                    see ytfzf(1) for a list of viewers.

        --async-thumbnails      Download thumbnails asynchronously.

        --skip-thumb-download   Skips the process of downloading thumbnails

        --thumbnail-quality=<quality>
                                Select quality of thumbnails,
                                can be:
                                    maxres
                                    maxresdefault
                                    sddefault
                                    high (default)
                                    medium
                                    default
                                    start
                                    middle
                                    end

        -i <interface>          The interface to use (default: text)

        -D                      Alias for -i ext

        -a                      Automatically select the first video

        -r                      Automatically select a random video

        -A                      Select all videos

        -S <sed address>        Automatically selects a specific video
                                    based on a given sed address

        -n <video count>        The amount of videos to select with -a and -r

        --preview-side=<side>   The side to show the preview on in fzf:
                                    left
                                    right
                                    up
                                    down
        --fancy-subs             Adds a divider between each subscription
                                 when scraping subscriptions

        --sort                   Sorts video results by a sort name,
                                    The default sort name is upload-date
                                    To change sort names use --sort=<name>

        --sort-name=<name>       Load a different sorting algorithm for --sort
                                    To see usable sort-names, use --list-addons

        --disable-submenus       Whether or not to disable submenus,
                                 which are menus for results like:
                                    playlists and channels

        --disable-back           Disables the back button in submenus

        --disable-actions        Disables actions such as submenus, and the back button.

        --keep-vars              Options passed to ytfzf are kept in submenus.

        --submenu-opts=<opts>    ytfzf options to pass to submenus.

    SEARCH OPTIONS:
        -s                      After closing fzf make another search

        -q                      Use a search query from search history
                                see ytfzf(1) for more info.

        --search-source=<source>
                                The place to get the search from
                                see ytfzf(1) for more information

        --multi-search          Allow multiple searches seperated by ,

        --pages                 The amount of pages to scrape
                                    does not work with some scrapers.
        --pages-start=<page>    The page number to start on

        --odysee-video-count    The amount of videos to scrape from odysee

        --nsfw                  Enable nsfw videos (odysee only)

        --sort-by=<sort>        Searches for videos sorted by:
                                    relevance
                                    rating (youtube only)
                                    upload_date
                                    oldest_first (odysee only)
                                    view_count (youtube only)

        --upload-date=<time>    Searches for videos that were uploaded:
                                    hour
                                    today
                                    week
                                    month
                                    year

        --video-duration=<time> Searches for vidos that are:
                                    short
                                    medium
                                    long

        --type=<type>           Searches for uploads of type:
                                    video
                                    playlist
                                    channel
                                    all

        --features=<features>   Searches for videos with features:
                                    hd
                                    subtitles
                                    creative_commons
                                    3d
                                    live
                                    4k
                                    360
                                    location
                                    hdr

        --region=<country-code> The region to search.

        -c <scraper>            The scraper to use,
                                    See ytfzf(1) for a list of builtin scrapers
                                    you can use multiple scrapers
                                    by separating each with a comma, eg:
                                        youtube,odysee

        --scrape+=<scraper>     Use another scraper

        --scrape-=<scraper>     Dont use a scraper.

        -H                      alias for -c H

        --ii=<instance>         The invidious instance to use for scraping.

        --force-youtube         Converts invidious links to youtube links
                                before playing (enabled by default)

        --force-invidious       Uses the chosen invidious instance
                                instead of converting to a youtube link

    ADDON OPTIONS:
        -e <extention>          Load an extention

        --list-addons            Show available addons

    MISC OPTIONS:
        -x                       Clear search and watch history

        --history-clear=<type>   Clear either search, or watch  history.

        --max-threads=<count>    The amount of threads that should be spawned
                                 at any given time.

        --single-threaded        Same as --max-threads=1

        --rii                   Refreseh invidious instance cache

        --available-inv-instances
                                Shows the invidious instances
                                that ytfzf may pick from

        --keep-cache            Do not delete the cache files.

        --thumbnail-log         Write thumbnail errors to this file.

    See ytfzf(1) and ytfzf(5) for more information.
"
}

handle_playing_notifications() {
	# if no notify-send push error to /dev/null
	if [ "$#" -le 1 ]; then
		unset IFS
		while read -r id title; do
			notify-send -c ytfzf -i "$thumb_dir/${id}.jpg" "Ytfzf Info" "Opening: $title" 2>/dev/null
		done <<-EOF
			    $(jq -r '.[]|select(.url=="'"$*"'")|"\(.ID)\t\(.title)"' <"$ytfzf_video_json_file")
		EOF
	else
		notify-send -c ytfzf "ytfzf info" "Opening: $# videos" 2>/dev/null
	fi
}

on_open_url_handler___ytfzf__() {
	[ "$notify_playing" -eq 1 ] && handle_playing_notifications "$@"
}

on_clean_up___ytfzf__() {
	# print_info "cleaning up\n"
	# clean up only as parent process
	# kill ytfzf sub process{{{
	# I think this needs to be written to a file because of sub-shells
	jobs_file="${YTFZF_TEMP_DIR}/the-jobs-need-to-be-written-to-a-file-$$.list"
	jobs -p >"$jobs_file"
	while read -r line; do
		[ "$line" ] && kill "$line" 2>/dev/null
	done <"$jobs_file"
	rm -f "$jobs_file"
	#}}}
    if [ "$__is_fzf_preview" -eq 0 ]; then
        [ "$keep_cache" -eq 1 ] && print_debug "[CLEAN UP]: copying cache dir${new_line}" && cp -r "${session_cache_dir}" "${cache_dir}"
	    [ -d "$session_cache_dir" ] && rm -rf "$session_cache_dir"
    fi
}

on_load_fake_extension___ytfzf__() {
	#these need to be here, because it modifies stuff for _getopts
	#also no harm done because enable_hist cannot be set to true with an --option

	#do not check if hist is enabled, because on_load_fake_extension___ytfzf_history__ does that
	load_fake_extension "__ytfzf_history__" "1"
	load_fake_extension "__ytfzf_search_history__" "1"
}

on_post_set_vars___ytfzf__() {
	[ -z "$ytdl_path" ] && { command_exists "yt-dlp" && ytdl_path="yt-dlp" || ytdl_path="youtube-dl"; }

	: "${ytdl_pref:=$video_pref+$audio_pref/best/$video_pref/$audio_pref}"

	: "${shortcut_binds="Enter,double-click,${download_shortcut},${video_shortcut},${audio_shortcut},${detach_shortcut},${print_link_shortcut},${show_formats_shortcut},${info_shortcut},${search_again_shortcut},${custom_shortcut_binds},${custom_shortcut_binds}"}"

	[ ! -d "$cache_dir" ] && mkdir -p "$cache_dir"

	# If file doesn't already exist (or if force-refresh is requested), cURL and cache it.
	# CHECK: implement check for force-request
	# CHECK: added --refresh-inv-instances to optargs
	[ ! -f "$instances_file" ] && refresh_inv_instances

	: "${invidious_instance:=$(get_random_invidious_instance)}"

    #if there is no domain, use the chosen invidious instance
    [ -z "${yt_video_link_domain}" ] && yt_video_link_domain="${invidious_instance}"

	export FZF_DEFAULT_OPTS="--margin=0,3,0,0 $FZF_DEFAULT_OPTS"

	[ "$multi_search" -eq 1 ] && load_fake_extension "__ytfzf_multisearch__"

	scrape_search_exclude="${scrape_search_exclude}${custom_scrape_search_exclude} "

	source_scrapers

	print_debug "${new_line}=============${new_line}VARIABLE DUMP${new_line}=============${new_line}"
	print_debug "$(set)${new_line}"
	print_debug "${new_line}============${new_line}END VAR DUMP${new_line}============${new_line}"
}
#}}}

# __ytfzf_multisearch__ extension {{{

on_init_search___ytfzf_multisearch__() {
	prepare_for_set_args ","
	# shellcheck disable=SC2086
	set -- $1
	end_of_set_args
	__total_search_count="$#"
	printf "%s\n" "$@" >"${session_cache_dir}/searches.list"
	# if we get rid of everything up to the first comma, and it's empty or equal to the original, there is 1 scrape
	if [ "$__total_scrape_count" -lt "$__total_search_count" ]; then
		scrape=$(mul_str "${scrape}," "$(($(wc -l <"${session_cache_dir}/searches.list") / __total_scrape_count))")
		set_scrape_count
	fi
}

ext_on_search___ytfzf_multisearch__() {
	get_search_from_source "next"
}

get_search_from_next() {
	_search=$(head -n "$__scrape_count" "${session_cache_dir}/searches.list" | tail -n 1)
}

# }}}

# __ytfzf_history_management__ {{{

on_load_fake_extension___ytfzf_history_management__() {
	on_opt_parse_x() {
		clear_hist "${1:-all}"
		exit 0
	}
	on_opt_parse_hist_clear() { on_opt_parse_x "$@"; }

	clear_hist() {
		case "$1" in
		search)
			: >"$search_hist_file"
			print_info "Search history cleared${new_line}"
			;;
		watch)
			: >"$hist_file"
			print_info "Watch history cleared${new_line}"
			;;
		*)
			: >"$search_hist_file"
			: >"$hist_file"
			print_info "History cleared${new_line}"
			;;
		esac
	}
}
# }}}

# __ytfzf_history__ extension {{{
on_load_fake_extension___ytfzf_history__() {

	! extension_is_loaded "__ytfzf_history_management__" && load_fake_extension "__ytfzf_history_management__"

	: "${hist_file:="$cache_dir/watch_hist"}"
	on_opt_parse_history() {
		if [ "$enable_hist" -eq 0 ]; then
			die 1 "enable_hist must be set to 1 for -H/--history${new_line}"
		fi
		scrape=history
	}
	on_opt_parse_H() {
		on_opt_parse_history "$@"
	}
}

on_open_url_handler___ytfzf_history__() {
	add_to_hist "$ytfzf_video_json_file" <"$ytfzf_selected_urls"
}

add_to_hist() {
	[ "$enable_hist" -eq 1 ] || return
	print_debug "[WATCH HIST]: adding to file $hist_file${new_line}"
	# id of the video to add to hist will be passed through stdin
	# if multiple videos are selected, multiple ids will be present on multiple lines
	json_file="$1"
    urls="$(printf '"%s",' $(cat))"
    urls="[${urls%,}]"
	jq -r '[ .[]|select(.url as $url | '"$urls"' | index($url) >= 0)]' <"$json_file" | sed "/\[\]/d" | sed "2s/$/\n    \"viewed\": \"$(date +'%m\/%d\/%y\ %H\:%M\:%S\ %z')\",/" >>"$hist_file"
	unset url urls json_file
}

scrape_history() {
	enable_hist=0 # enabling history while scrape is history causes issues
	scrape_json_file "$hist_file" "$2"
	cp "$2" "$2.tmp"
	jq -s '[.[]|.[]+{scraper: "watch_history"}]' <"$2.tmp" >"$2"
	rm "$2.tmp"
}
scrape_H() { scrape_history "$@"; }

video_info_text_watch_history() {
	viewed_len=19

	[ "${views#"|"}" -eq "${views#"|"}" ] 2>/dev/null && views="|$(printf "%s" "${views#"|"}" | add_commas)"
	printf "%-${title_len}.${title_len}s\t" "$title"
	printf "%-${channel_len}.${channel_len}s\t" "$channel"
	printf "%-${dur_len}.${dur_len}s\t" "$duration"
	printf "%-${view_len}.${view_len}s\t" "$views"
	printf "%-${date_len}.${date_len}s\t" "$date"
	printf "%-${viewed_len}.${viewed_len}s\t" "$viewed"
	printf "%s" "$url"
	printf "\n"
}
# }}}

# __ytfzf_search_history__ extension {{{

on_load_fake_extension___ytfzf_search_history__() {

	! extension_is_loaded "__ytfzf_history_management__" && load_fake_extension "__ytfzf_history_management__"

	: "${search_hist_file:="$cache_dir/search_hist"}"
	on_opt_parse_q() {
		if [ "$enable_search_hist" -eq 0 ]; then
			die 1 'In order to use this search history must be enabled${new_line}'
		fi
		[ ! -s "$search_hist_file" ] && die 1 "You have no search history${new_line}"
		search_source="hist"
	}
	on_opt_parse_search_hist() {
		on_opt_parse_q "$@"
	}
}

on_post_set_vars___ytfzf_search_history__() {
	[ "${use_search_hist:-0}" -eq 1 ] && print_warning "use_search_hist is deprecated, please use search_source=hist instead${new_line}" && search_source=hist
}

on_init_search___ytfzf_history__() {
	[ "$enable_search_hist" -eq 1 ] && [ -n "$_search" ] && [ "$__is_submenu" -eq 0 ] && [ "$__is_fzf_preview" -eq 0 ] && handle_search_history "$_search" "$search_hist_file"
}

get_search_from_hist() {
	_search="$(parse_search_hist_file <"$search_hist_file" | quick_menu_wrapper)"
}

parse_search_hist_file() {
	awk -F"${tab_space}" '{ if ($2 == "") {print $1} else {print $2} }'
}

handle_search_history() {
	printf "%s${tab_space}%s\n" "$(date +'%D %H:%M:%S %z')" "${1}" >>"$2"
}

# }}}

# Utility functions {{{

############################
#    UTILITY FUNCTIONS     #
############################

# In order to be a utility function it must meet the following requirements:
# Does not have side effects
# Can be redefined by the user in an extension or config file

## Jq util{{{
jq_pad_left='
def pad_left(n; num):
    num | tostring |
        if (n > length) then ((n - length) * "0") + (.) else . end
'
# }}}

# Invidious{{{
refresh_inv_instances() {
	print_info "Fetching list of healthy invidious instances ...${new_line}" &&
		# The pipeline does the following:
		#   - Fetches the avaiable invidious instances
		#   - Gets the one where the api is public
		#   - Puts them in a list
		curl -X GET -sSf "$instances_url" | jq -r '[.[]|select(.[1].api==true)|.[1].uri]|join("\n")' >"$instances_file"
}

get_invidious_instances() {
	cat "$instances_file"
}

get_random_invidious_instance() {
	shuf "$instances_file" | head -n 1
}
# }}}

# General Scraping{{{
_get_request() {
	_base_url=$1
	shift 1
	# Get search query from youtube
	curl -f "$_base_url" -s -L \
		"$@" \
		-H "User-Agent: $useragent" \
		-H 'Accept-Language: en-US,en;q=0.9' \
		--compressed
}

create_sorted_video_data() {
	jq -c -r 'select(.!=[])|.[]' <"$ytfzf_video_json_file" | sort_video_data_fn
}

download_thumbnails() {
	[ "$skip_thumb_download" -eq 1 ] && {
		print_info "Skipping thumbnail download${new_line}"
		return 0
	}
	[ "$async_thumbnails" -eq 0 ] && print_info "Fetching thumbnails...${new_line}"
	curl_config_file="${session_temp_dir}/curl_config"
	[ -z "$*" ] && return 0
	: >"$curl_config_file"
	for line in "$@"; do
		printf "url=\"%s\"\noutput=\"$thumb_dir/%s.jpg\"\n" "${line%%';'*}" "${line##*';'}"
	done >>"$curl_config_file"
	curl -fLZ -K "$curl_config_file"
	[ $? -eq 2 ] && curl -fL -K "$curl_config_file"
}

get_missing_thumbnails() {
	# this function could be done in a more pure-shell way, however it is extremely slow
	_tmp_id_list_file="${session_temp_dir}/all-ids.list"
	_downloaded_ids_file="${session_temp_dir}/downloaded-ids.list"

	# gets all ids and writes them to file
	jq -r '.[]|select(.thumbs!=null)|.ID' <"$ytfzf_video_json_file" | sort | uniq >"$_tmp_id_list_file"
	# gets thumb urls, and ids, and concatinates them such as: <thumbnail>;<id>
	# essencially gets all downloaded thumbnail ids, by checking $thumb_dir and substituting out the \.jpg at the end
	find "$thumb_dir" -type f | sed -n 's/^.*\///; s/\.jpg$//; /^[^\/]*$/p' | sort >"$_downloaded_ids_file"

	# Finds ids that appear in _tmp_id_list_file only
	# shellcheck disable=SC2089
	missing_ids="\"$(diff "$_downloaded_ids_file" "$_tmp_id_list_file" | sed -n 's/^[>+] *\(.*\)$/\1/p')\""

	# formats missing ids into the format: <thumb-url>;<id>
	jq --arg ids "$missing_ids" -r '.[]|select(.thumbs!=null)|select(.ID as $id | $ids | contains($id))|.thumbs + ";" + .ID' <"$ytfzf_video_json_file"

	unset _tmp_id_list_file _downloaded_ids_file missing_ids
}
# }}}

#arg/ifs manipulation{{{
prepare_for_set_args() {
	OLD_IFS=$IFS
	[ "$1" = "" ] && unset IFS || IFS=$1
	set -f
}
end_of_set_args() {
	IFS=$OLD_IFS
}

modify_ifs() {
	OLD_IFS=$IFS
	IFS=${1:-" ${tab_space}${new_line}"}
}
end_modify_ifs() {
	IFS=$OLD_IFS
}
# }}}

#general util{{{

_get_real_channel_link() {
	_input_link=$(trim_blank "$1")

	case "$1" in
	http?://*/@*)
		domain=${_input_link#https://}
		domain=${domain%%/*}
        url=$(printf "https://www.youtube.com/channel/%s\n" "$(_get_request "$_input_link" | sed -n 's/.*"channelId":"\([^"]\+\).*/\1/p')")
        _get_real_channel_link_handle_empty_real_path () {
            printf "$url"
        }
		;;
	http?://*/c/* | http?://*/user/* | *\.*)
		domain=${_input_link#https://}
		domain=${domain%%/*}
		url=$(printf "%s" "$_input_link" | sed 's_\(https://\)*\(www\.\)*youtube\.com_'"${invidious_instance}"'_')
		_get_real_channel_link_handle_empty_real_path() {
			printf "https://%s\n" "${1#https://}"
		}
		;;
	[Uu][Cc]??????????????????????/videos | [Uu][Cc]?????????????????????? | *channel/[Uu][Cc]?????????????????????? | *channel/[Uu][Cc]??????????????????????/videos)
		id="${_input_link%/videos}"
		id="${id%/playlists}"
		id="${id%/streams}"
		id="${id##*channel/}"
		print_warning "$_input_link appears to be a youtube id, which is hard to detect, please use a full channel url next time${new_line}"
		domain="youtube.com"
		url=$(printf "https://youtube.com/channel/%s/videos" "$id" | sed 's_\(https://\)*\(www\.\)*youtube\.com_'"${invidious_instance}"'_')
		_get_real_channel_link_handle_empty_real_path() {
			printf "%s\n" "https://${domain}/channel/${id}/videos"
		}
		;;
	"@"*)
		for link in "https://www.youtube.com/user/${1#"@"}" "https://www.youtube.com/c/${1#"@"}"; do
			_real_link="$(_get_real_channel_link "$link")"
			if [ "$_real_link" != "$link" ]; then
				printf "%s\n" "$_real_link"
				return 0
			fi
		done
		return 1
		;;
	*)
		_get_real_channel_link_handle_empty_real_path() {
			printf "$1\n"
		}
		;;
	esac

	real_path="$(curl -is "$url" | sed -n 's/^[Ll]ocation: //p' | sed 's/[\n\r]$//g')"
	# prints the origional url because it was correct
	if [ -z "$real_path" ]; then
		_get_real_channel_link_handle_empty_real_path "$_input_link"
		return 0
	fi
	printf "%s\n" "https://${domain}${real_path}"
}

trim_url() {
	while IFS= read -r _line; do
		printf '%s\n' "${_line##*"|"}"
	done
}

trim_blank() { _s="${1##[[:blank:]]}"; printf '%s' "${_s%%[[:blank:]]}"; }


command_exists() {
	command -v "$1" >/dev/null 2>&1
}

is_relative_dir() {
	case "$1" in
	../* | ./* | ~/* | /*) return 0 ;;
	esac
	return 1
}

get_key_value() {
	sep="${3:- }"
	value="${1##*"${sep}""${2}"=}"
	# this can be used similarly to how you use $REPLY in bash
	KEY_VALUE="${value%%"${sep}"*}"
	printf "%s" "$KEY_VALUE"
	unset value
	[ "$KEY_VALUE" ]
	return "$?"
}

# capitalizes the first letter of a string
title_str() {
	awk '{printf "%s%s\n", toupper(substr($1,0,1)), substr($1,2)}' <<-EOF
		    $1
	EOF
}

# backup shuf function, as shuf is not posix
command_exists "shuf" || shuf() {
	#make awk read from fd 3, fd 3 will read $1 if exists, or stdin
	[ "$1" ] && exec 3<"$1" || exec 3<&0
	awk -F'\n' 'BEGIN{srand()} {print rand() " " $0}' <&3 | sort -n | sed 's/[^ ]* //'
	exec 3<&-
}

add_commas() {
	awk '
		{
            for(i=0; i<length($1); i++){
				if(i % 3 == 0 && i!=0){
                    printf ","
				}
                printf "%s", substr($1, length($1) - i, 1)
			}
		}

		END{
            print ""
		}' |
		awk '
            {
                for (i=length($1); i>0; i--){
                    printf "%s", substr($1, i, 1)
                }
            }
        '
}

mul_str() {
	str=$1
	by=$2
	new_str="$str"
	mul_str_i=1
	while [ "$mul_str_i" -lt "$by" ]; do
		new_str="${new_str}${str}"
		mul_str_i=$((mul_str_i + 1))
	done
	printf "%s" "$new_str"
	unset mul_str_i new_str by str
}

detach_cmd() {
	nohup "$@" >"/dev/null" 2>&1 &
}

remove_ansi_escapes() {
	sed -e 's/[[:cntrl:]]\[\([[:digit:]][[:digit:]]*\(;\|m\)\)*//g'
}
# }}}

#Menu stuff{{{
quick_menu() {
	fzf --ansi --reverse --prompt="$1"
}
quick_menu_ext() {
	external_menu "$1"
}

info_wait_prompt() {
	printf "%s\n" "quit [q]" "quit (override -l) [Q]" "open menu [c]" "play [enter]"
	read -r info_wait_action
}
info_wait_prompt_ext() {
	info_wait_action=$(printf "%s\n" "quit: q" "quit (override -l): Q" "open menu: c" "play: enter" | quick_menu_wrapper "Choose action" | sed -e 's/enter//' -e 's/^.*: \(.*\)$/\1/p' | tr -d '[:space:]')
}

display_text() {
	printf "%s\n" "$@"
}
display_text_ext() {
	display_text "$@"
}

display_text_wrapper() {
	generic_wrapper "display_text" "$@"
}

info_wait_prompt_wrapper() {
	generic_wrapper "info_wait_prompt" "$@"
}

search_prompt_menu_wrapper() {
	generic_wrapper "search_prompt_menu" "$@"
}

quick_menu_wrapper() {
	generic_wrapper "quick_menu" "$1"
}

generic_wrapper() {
	base_name=$1
	shift
	fn_name="$base_name""$(printf "%s" "${interface:+_$interface}" | sed 's/-/_/g')"
	if command_exists "$fn_name"; then
		print_debug "[INTERFACE]: Running menu function: $fn_name${new_line}"
		$fn_name "$@"
	else
		print_debug "[INTERFACE]: Menu function $fn_name did not exist, falling back to ${base_name}_ext${new_line}"
		"$base_name"_ext "$@"
	fi
	unset fn_name
}

# The menu to use instead of fzf when -D is specified
external_menu() {
	# dmenu extremely laggy when showing tabs
	tr -d '\t' | remove_ansi_escapes | dmenu -i -l 30 -p "$1"
}

search_prompt_menu() {
	printf "Search\n> " >/dev/stderr
	read -r _search
	printf "\033[1A\033[K\r%s\n" "> $_search" >/dev/stderr
}
search_prompt_menu_ext() {
	_search="$(printf '' | external_menu "Search: ")"
}

run_interface() {

	if [ "$show_thumbnails" -eq 1 ]; then
		prepare_for_set_args
		case "$async_thumbnails" in
		0) download_thumbnails $(get_missing_thumbnails) ;;
		1) download_thumbnails $(get_missing_thumbnails) >/dev/null 2>&1 & ;;
		esac
		end_of_set_args
	fi

	_interface="interface_${interface:-text}"

	print_debug "[INTERFACE]: Running interface: $_interface${new_line}"

	$(printf "%s" "$_interface" | sed 's/-/_/g') "$ytfzf_video_json_file" "$ytfzf_selected_urls"
	unset _interface
}

_init_video_info_text() {
	TTY_COLS=$1

    command_exists "column" && use_column=1 || {
        use_column=0
        print_warning "command \"column\" not found, the menu may look very bad${new_line}"
    }

	title_len=$((TTY_COLS / 2))
	channel_len=$((TTY_COLS / 5))
	dur_len=7
	view_len=10
	date_len=14
}

_post_video_info_text() {
	if [ "$use_column" = "1" ] ; then
		column -t -s "$tab_space"
	else
		cat
	fi
}

_video_info_text() {
	[ "${views#"|"}" -eq "${views#"|"}" ] 2>/dev/null && views="|$(printf "%s" "${views#"|"}" | add_commas)"
	printf "%-${title_len}.${title_len}s\t" "$title"
	printf "%-${channel_len}.${channel_len}s\t" "$channel"
	printf "%-${dur_len}.${dur_len}s\t" "$duration"
	printf "%-${view_len}.${view_len}s\t" "$views"
	printf "%-${date_len}.${date_len}s\t" "$date"
	printf "%s" "$url"
	printf "\n"
}

#This function generates a series of lines that will be displayed in fzf, or some other interface
#takes in a series of jsonl lines, each jsonl should follow the VIDEO JSON FORMAT
video_info_text() {
	jq -r '[.title, .channel, .duration, .views, .date, .viewed, .url, .scraper]|join("\t|")' | while IFS="$tab_space" read -r title channel duration views date viewed url scraper; do
		scraper="${scraper#"|"}"
		fn_name=video_info_text_"${scraper}"
		if command_exists "$fn_name"; then
			"$fn_name" "$title" "$channel" "$duration" "$views" "$date" "$viewed" "$url" "$scraper"
		else
			_video_info_text "$title" "$channel" "$duration" "$views" "$date" "$viewed" "$url" "$scraper"
		fi
	done
	unset title channel duration views date viewed url scraper
}

# This is completely unrelated to video_info_text
# It is used in preview_img for when text should appear in the preview in fzf
thumbnail_video_info_text() {
	[ "$views" -eq "$views" ] 2>/dev/null && views="$(printf "%s" "$views" | add_commas)"
	[ -n "$title" ] && printf "\n ${c_cyan}%s" "$title"
	[ -n "$channel" ] && printf "\n ${c_blue}Channel  ${c_green}%s" "$channel"
	[ -n "$duration" ] && printf "\n ${c_blue}Duration ${c_yellow}%s" "$duration"
	[ -n "$views" ] && printf "\n ${c_blue}Views    ${c_magenta}%s" "$views"
	[ -n "$date" ] && printf "\n ${c_blue}Date     ${c_cyan}%s" "$date"
	[ -n "$viewed" ] && printf "\n ${c_blue}Viewed   ${c_cyan}%s" "$viewed"
	[ -n "$description" ] && printf "\n ${c_blue}Description ${c_reset}: %s" "$(printf "%s" "$description" | sed 's/\\n/\n/g')"
}
# }}}

# Extension stuff{{{

do_an_event_function() {
	event="$1"
	shift
	print_debug "[EVENT]: doing event: $event${new_line}"
	command_exists "$event" && $event "$@"
	prepare_for_set_args " "
	for ext in $loaded_extensions; do

		command_exists "${event}_$ext" && print_debug "[EVENT]: $ext running $event${new_line}" && "${event}_$ext" "$@"
	done
	end_of_set_args
}

source_scrapers() {
	prepare_for_set_args ","
	for _scr in $scrape; do
		if [ -f "$YTFZF_CUSTOM_SCRAPERS_DIR/$_scr" ]; then
			# shellcheck disable=SC1090
			. "${YTFZF_CUSTOM_SCRAPERS_DIR}/$_scr"
		elif [ -f "$YTFZF_SYSTEM_ADDON_DIR/scrapers/$_scr" ]; then
			# shellcheck disable=SC1090
			. "${YTFZF_SYSTEM_ADDON_DIR}/scrapers/$_scr"
		fi
		[ "$__is_fzf_preview" -eq 0 ] && command_exists "on_startup_$_scr" && "on_startup_$_scr"
		print_debug "[LOADING]: Loaded scraper: $_scr${new_line}"
	done
	end_of_set_args
}

extension_is_loaded() {
	case "$loaded_extensions" in
	#the extension may be at the middle, beginning, or end
	#spaces must be accounted differently
	*" $1 "* | "$1 "* | *" $1") return 0 ;;
	*) return 1 ;;
	esac
}

load_extension() {
	ext=$1
	loaded_extensions="$loaded_extensions $(printf "%s" "${ext##*/}" | sed 's/[ -]/_/g')"
	loaded_extensions="${loaded_extensions# }"

	prepare_for_set_args
	for path in "${YTFZF_EXTENSIONS_DIR}/${ext}" "${YTFZF_SYSTEM_ADDON_DIR}/extensions/${ext}" "${ext}"; do
		if [ -f "${path}" ]; then
			__loaded_path="${path}" . "${path}"
			rv="$?"
			break
		else
			rv=127
		fi
	done
	end_of_set_args

	print_debug "[LOADING]: loaded extension: ${ext} with exit code: ${rv}${new_line}"

	return $rv
}

#for extensions succh as __ytfzf__
load_fake_extension() {
	_should_be_first="$2"
	if [ "${_should_be_first:-0}" -eq 1 ]; then
		loaded_extensions="$1 ${loaded_extensions}"
	else
		loaded_extensions="${loaded_extensions} $1"
		loaded_extensions="${loaded_extensions# }"
	fi

	command_exists "on_load_fake_extension_$1" && on_load_fake_extension_"$1"
	print_debug "[LOADING]: fake extension: $1 loaded${new_line}"
}

load_sort_name() {
	_sort_name=$1
	# shellcheck disable=SC1090
	# shellcheck disable=SC2015
	case "$_sort_name" in
	./* | ../* | /* | ~/*) command_exists "$_sort_name" && . "$_sort_name" ;;
	*)
		if [ -f "${YTFZF_SORT_NAMES_DIR}/${_sort_name}" ]; then
			. "${YTFZF_SORT_NAMES_DIR}/${_sort_name}"
		elif [ -f "${YTFZF_SYSTEM_ADDON_DIR}/sort-names/${_sort_name}" ]; then
			. "${YTFZF_SYSTEM_ADDON_DIR}/sort-names/${_sort_name}"
		else
			false
		fi
		;;
	esac
	rv="$?"
	unset "$_sort_name"
	print_debug "[LOADING]: loaded sort name: ${_sort_name} with exit code: ${rv}${new_line}"
	return "$rv"
}

load_url_handler() {
	requested_url_handler=$1
	if command_exists "$requested_url_handler"; then
		url_handler="${requested_url_handler:-multimedia_player}"
	else
		for path in "$YTFZF_URL_HANDLERS_DIR" "$YTFZF_SYSTEM_ADDON_DIR/url-handlers"; do
			[ -f "${path}/${requested_url_handler}" ] && url_handler="${path}/${requested_url_handler}" && return
		done
		die 2 "$1 is not a url-handler${new_line}"
	fi
	print_debug "[LOADING]: loaded url handler: ${requested_url_handler}${new_line}"
}

load_interface() {
	requested_interface="$1"
	# if we don't check which interface, itll try to source $YTFZF_CUSTOM_INTERFACES_DIR/{ext,scripting} which won't work
	# shellcheck disable=SC1090
	case "$requested_interface" in
	"ext" | "scripting" | "")
		interface=$requested_interface
		true
		;;
	./* | ../* | /* | ~/*)
		[ -f "$requested_interface" ] && . "$requested_interface" && interface="${requested_interface##*/}"
		false
		;;
	*)
		if [ -f "${YTFZF_CUSTOM_INTERFACES_DIR}/${requested_interface}" ]; then
			interface=$requested_interface
			. "$YTFZF_CUSTOM_INTERFACES_DIR/$requested_interface"
		elif [ -f "${YTFZF_SYSTEM_ADDON_DIR}/interfaces/${requested_interface}" ]; then
			interface=$requested_interface
			. "${YTFZF_SYSTEM_ADDON_DIR}/interfaces/${requested_interface}"
			true
		fi
		;;
	esac
	rv="$?"
	unset requested_interface
	print_debug "[LOADING]: loaded interface: ${requested_interface}${new_line}"
	return "$rv"
}

load_thumbnail_viewer() {
	_thumbnail_viewer="$1"
	case "$_thumbnail_viewer" in
	# these are special cases, where they are not themselves commands
	chafa-16 | chafa | chafa-tty | catimg | catimg-256 | imv | ueberzug | iterm2 | swayimg | mpv | sixel | kitty | sway | wayland)
		thumbnail_viewer="$_thumbnail_viewer"
		true
		;;
	swayimg-hyprland)
		print_warning "swayimg-hyprland thumbnail viewer may mess up any rules you have for swayimg${new_line}"
		thumbnail_viewer="$_thumbnail_viewer"
		;;
	./* | /* | ../* | ~/*)
		thumbnail_viewer="$_thumbnail_viewer"
		false
		;;
	*)
		if [ -f "${YTFZF_THUMBNAIL_VIEWERS_DIR}/${_thumbnail_viewer}" ]; then
			thumbnail_viewer="${YTFZF_THUMBNAIL_VIEWERS_DIR}/${_thumbnail_viewer}"
		else
			thumbnail_viewer="${YTFZF_SYSTEM_ADDON_DIR}/thumbnail-viewers/$_thumbnail_viewer"
		fi
		false
		;;
	esac
	rv="$?"
	print_debug "[LOADING]: loaded thumbnail viewer: ${_thumbnail_viewer}${new_line}"
	unset _thumbnail_viewer
	return $rv
}
#}}}

# Logging {{{

_print_to_log_and_stderr () {
    tee -a "${YTFZF_LOGFILE:-/dev/null}" <<EOF >&2
$(printf -- "$1")
EOF
}

print_debug() {
    [ "${YTFZF_LOGFILE}" ] && pre_text="[DEBUG]" || pre_text="${c_blue}[DEBUG]${c_reset}"
    [ "$log_level" -ge 3 ] && _print_to_log_and_stderr "${pre_text}: $1"
    return 0
}
print_info() {
    [ "$log_level" -ge 2 ] && _print_to_log_and_stderr "$1"
}
print_warning() {
    [ "${YTFZF_LOGFILE}" ] && pre_text="[WARNING]" || pre_text="${c_yellow}[WARNING]${c_reset}"
    [ "$log_level" -ge 1 ] && _print_to_log_and_stderr "${pre_text}: $1"
}
print_error() {
    [ "${YTFZF_LOGFILE}" ] && pre_text="[ERROR]" || pre_text="${c_red}[ERROR]${c_reset}"
    [ "$log_level" -ge 0 ] && _print_to_log_and_stderr "${pre_text}: $1"
}

die() {
	_return_status=$1
	print_error "$2"
	exit "$_return_status"
}

#}}}

# urlhandlers{{{
# job of url handlers is:
# handle the given urls, and take into account some requested attributes, eg: video_pref, and --detach
# print what the handler is doing
video_player() {
	# this function should not be set as the url_handler as it is part of multimedia_player
	command_exists "mpv" || die 3 "mpv is not installed\n"
	[ "$is_detach" -eq 1 ] && use_detach_cmd=detach_cmd || use_detach_cmd=''
	# shellcheck disable=SC2086
	unset IFS
	$use_detach_cmd mpv --ytdl-format="$ytdl_pref" $(eval echo "$url_handler_opts") "$@"
}

audio_player() {
	# this function should not be set as the url_handler as it is part of multimedia_player
	command_exists "mpv" || die 3 "mpv is not installed\n"
	# shellcheck disable=SC2086
	unset IFS
	case "$is_detach" in
	0) mpv --no-video --ytdl-format="$ytdl_pref" $(eval echo "$url_handler_opts") "$@" ;;
	1) detach_cmd mpv --force-window --no-video --ytdl-format="$ytdl_pref" $(eval echo "$url_handler_opts") "$@" ;;
	esac
}

multimedia_player() {
	# this function differentiates whether or not audio_only was requested
	case "$is_audio_only" in
	0) video_player "$@" ;;
	1) audio_player "$@" ;;
	esac
}

downloader() {
	command_exists "${ytdl_path}" || die 3 "${ytdl_path} is not installed\n"
	[ "$is_detach" -eq 1 ] && use_detach_cmd=detach_cmd || use_detach_cmd=''
	prepare_for_set_args
	# shellcheck disable=SC2086
	case $is_audio_only in
	0) $use_detach_cmd "${ytdl_path}" -f "${ytdl_pref}" $ytdl_opts "$@" ;;
	1) $use_detach_cmd "${ytdl_path}" -x -f "${audio_pref}" $ytdl_opts "$@" ;;
	esac && _success="finished" || _success="failed"
	[ "$notify_playing" -eq 1 ] && notify-send -c ytfzf "Ytfzf Info" "Download $_success"

	end_of_set_args
}
# }}}

# Searching {{{
get_search_from_source() {
	source=$1
	shift
	prepare_for_set_args ":"
	for src in $source; do
		end_of_set_args
		case "$src" in
		args) _search="$initial_search" ;;
		prompt) search_prompt_menu_wrapper ;;
		fn-args) _search="$*" ;;
		*) command_exists "get_search_from_$src" && get_search_from_"$src" "$@" ;;
		esac
		[ "$_search" ] && break
	done
}

# }}}

#Misc{{{
clean_up() {
	do_an_event_function on_clean_up
}

usage() {
	unset IFS
	set -f
	for ext in $loaded_extensions; do
		if command_exists "print_help_$ext"; then
			printf "\n----%s----\n" "$ext"
			"print_help_$ext"
		fi
	done
}

# }}}
# }}}

# Traps {{{
[ $__is_fzf_preview -eq 0 ] && trap 'clean_up' EXIT
[ $__is_fzf_preview -eq 0 ] && trap 'exit' INT TERM HUP
#}}}

# Global Variables and Start Up {{{

set_vars() {

	check_exists="${1:-1}"

	# save the ecurrent environment so that any user set variables will be saved
	if [ "$check_exists" -eq 1 ]; then
		tmp_env="${YTFZF_TEMP_DIR}/ytfzf-env-$$"
		export -p >"$tmp_env"
	fi

	# debugging
	log_level="2" thumbnail_debug_log="/dev/null"

	# global vars

	gap_space="                                                                                                                   "
	new_line='
    ' tab_space=$(printf '\t')
	#necessary as a seperator for -W
	EOT="$(printf '\003')"

	if [ "${COLUMNS:-$TTY_COLS}" ] && [ "${LINES:-$TTY_LINES}" ]; then
		TTY_COLS="${COLUMNS:-$TTY_COLS}"
		TTY_LINES="${LINES:-$TTY_LINES}"
	elif command_exists "tput"; then
		TTY_COLS=$(tput cols 2>/dev/null)
		TTY_LINES=$(tput lines 2>/dev/null)
	elif [ "${stty_cols_lines:=$(stty size 2>/dev/null)}" ]; then #set the var here to avoid running stty size twice.
		TTY_LINES="${stty_cols_lines% *}"
		TTY_COLS="${stty_cols_lines#* }"
	else
		print_warning "Could not determine terminal size, defaulting to 80 COLUMNS x 25 LINES${new_line}"
		TTY_COLS=80
		TTY_LINES=25
	fi

	#config vars

	search_source=args:prompt

	# scraping
	useragent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.152 Safari/537.36"

	# menu options

	enable_submenus="1" submenu_opts="" submenu_scraping_opts="" enable_back_button="1"
	keep_vars=0

	interface=""

	fancy_subs="0" fancy_subs_left="-------------" fancy_subs_right="${fancy_subs_right=$fancy_subs_left}"

	fzf_preview_side="left" thumbnail_viewer="ueberzug"

	#actions are slow, disable if you want to increase runtime speed by 15ms
	enable_actions=1

	# shortcuts
	download_shortcut="alt-d" video_shortcut="alt-v" audio_shortcut="alt-m" detach_shortcut="alt-e" print_link_shortcut="alt-l" show_formats_shortcut="alt-f" info_shortcut="alt-i" search_again_shortcut="alt-s"

	next_page_action_shortcut="ctrl-p"

	# interface design
	show_thumbnails="0" is_sort="0" skip_thumb_download="0" external_menu_len="210"

	is_loop="0" search_again="0"

	# Notifications

	notify_playing="0"

	# directories
	cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/ytfzf" keep_cache="0"

	# history
	enable_hist="1" enable_search_hist="1"

	# format options
	# variable for switching on sort (date)
	is_detach="0" is_audio_only="0"
	url_handler="multimedia_player"
	url_handler_opts=""
	info_to_print="" info_wait="0" info_wait_action="q"
	video_pref="bestvideo" audio_pref="bestaudio"
	show_formats="0" format_selection_screen="simple" format_selection_sort="height"

	scripting_video_count="1"
	is_random_select="0" is_auto_select="0" is_specific_select="0"

	# option parsing
	long_opt_char="-"

	# scrape
	scrape="youtube"
	# this comes from invidious' api
	thumbnail_quality="high"
	sub_link_count="2"

	yt_video_link_domain="https://youtube.com"
	search_sort_by="relevance" search_upload_date="" search_video_duration="" search_result_type="video" search_result_features="" search_region="US"
	pages_to_scrape="" pages_start=""
	nsfw="false" odysee_video_search_count="30"

	multi_search="0"

	custom_scrape_search_exclude="" scrape_search_exclude=" youtube-subscriptions S SI SL T youtube-trending H history from-cache "

	max_thread_count="20"

	# When set to 1, instead of having to wait for thumbnails to download
	# The menu opens immediately while thumbnails download in the background
	async_thumbnails="0"

	#misc
	instances_url="https://api.invidious.io/instances.json?sort_by=type,health,api"
	instances_file="$cache_dir/instancesV2.json"

	# read from environment to reset any variables to what the user set
    
	if [ "$check_exists" -eq 1 ]; then
		_current_var_name=
		_current_var_value=
		while read -r _var; do
			[ -z "$_var" ] && continue
			case "$_var" in
			export" "*)
				[ "$_current_var_name" ] && {
					export "${_current_var_name}"="$(eval echo "$_current_var_value")"
					_current_var_name=""
					_current_var_value=""
				}
				_current_var_name="${_var#"export "}"
				_current_var_name="${_current_var_name%%=*}"
				_current_var_value="${_var#*=}"
				;;
            (*) _current_var_value="${_current_var_value}${new_line}${_var}" ;;
			esac
		done <"$tmp_env"

		rm "$tmp_env"
	fi
	unset check_exists _var _current_var_name _current_var_value
}

set_vars "${check_vars_exists}"

# hard dependency checks{{{
missing_deps=""
for dep in jq curl; do
	command_exists "$dep" || missing_deps="${missing_deps}, ${dep}"
done
[ "$missing_deps" ] && die 3 "You are missing the following required dependencies${missing_deps}, Please install them.${new_line}"
unset missing_deps
#}}}

# shellcheck disable=SC1090
[ -f "$YTFZF_CONFIG_FILE" ] && . "$YTFZF_CONFIG_FILE"

load_fake_extension "__ytfzf__" "1"

# }}}

# Scraping {{{

############################
#         SCRAPERS         #
############################

#############
# ARGUMENTS #
#############

# Scrapers take 2 arguments:
# 1: the search query (do not store in a variable called $_search, it is preferable to use $search, $c_search, or $const_search)
# Do not use the global $_search variable directly as $1 may be different.
# 2: the file to write the finished json to (the standard name for this variable is $output_json_file)

#############
#   FILES   #
#############

# Store all temp files in $session_temp_dir with a name prefix that matches the scraper name.
# Even better all temp files can be in $session_temp_dir/$scrape_name, no name prefix required.

##############
# EXIT CODES #
##############

# 0: success
# 1: failed to load website, or general error
# 100: :help search query
#----curl errors-----
# Even if not using curl, return these values.
# 6: Unresponsive website
# 22: General request error

####################
# RESPONSIBILITIES #
####################

# Scrapers are responsible for the following

# * If the search query is exactly: ":help", it should:
# 1. print a little information on what the scraper does, and how to use it
# 2. return 100

# * All other search words starting with : may be treated as special operators, you can do anything you want with them.
# * Currently :help is the only standard operator.

# * Lastly the scraper should create a json and store it in $2
# The required keys are:
# ID (string): (a unique identifier for the video can be anything really)
# url (string): the url that will be opened when the video is selected.
# title (string): The tittle of the video.
# scraper (string): the name of the scraper.
# Optional keys include:
# thumbs (string): Link to a thumbnail (no, "thumbs" is not a typo)
# channel (string): The author of the video (Should be human readable)
# duration (string): Length of the video (Should be human readable)
# views (string): view count
# date (string): The upload date (should be human readable).
# action (string): An action that should be read by the handle_actions function when the video is selected.
# For information on how to format an action, see the handle_actions function.

# Scraping backends {{{

_start_series_of_threads() {
	_thread_count=0
}

_thread_started() {
	_latest_fork="$1"
	_thread_count=$((_thread_count + 1))
	[ $_thread_count -ge $max_thread_count ] && wait "$_latest_fork" && _thread_count=$(jobs -p | wc -l)
}

set_real_channel_url_and_id() {
	_input_url="$1"
	case "$_input_url" in
	*/videos | */streams | */playlists) _input_url="${_input_url%/*}" ;;
	esac
	_id="$(_get_channel_id "$_input_url")"
	[ "$_id" = "$_input_url" ] &&
		_url="$(_get_real_channel_link "$_input_url")" && _id="$(_get_channel_id "$_url")"
	print_debug "[SCRAPE]: input url: $_input_url, detected url: $_url, detected id: $_id${new_line}"
	channel_url="$_url" channel_id="$_id"
	unset _url _id _input_url
}

#}}}

## Youtube  {{{
# Youtube backend functions {{{

_youtube_channel_name() {
	# takes channel page html (stdin) and returns the channel name
	sed -n 's/.*[<]title[>]\(.*\) - YouTube[<]\/title[>].*/\1/p' |
		sed \
			-e "s/&apos;/'/g" \
			-e "s/&#39;/'/g" \
			-e "s/&quot;/\"/g" \
			-e "s/&#34;/\"/g" \
			-e "s/&amp;/\&/g" \
			-e "s/&#38;/\&/g"
}

_youtube_get_json() {
	# Separates the json embedded in the youtube html page
	# * removes the content after ytInitialData
	# * removes all newlines and trims the json out
	sed -n '/var *ytInitialData/,$p' |
		tr -d '\n' |
		sed ' s_^.*var ytInitialData *=__ ; s_;</script>.*__ ;'
}

_youtube_channel_playlists_json() {
	channel_name="$1"
	jq ' [..|.items?|select(.!=null) | flatten(1) | .[] |
        {
            scraper: "youtube_channel_playlist",
            ID: .gridPlaylistRenderer.playlistId,
            thumbs: .gridPlaylistRenderer.thumbnail.thumbnails[0].url,
            title: .gridPlaylistRenderer.title.runs[0].text,
            channel: "'"$channel_name"'",
            url: "'"$yt_video_link_domain"'/playlist?list=\(.gridPlaylistRenderer.playlistId)",
            duration: "\(.gridPlaylistRenderer.videoCountText.runs[0].text) videos",
			action: "scrape type=invidious-playlist search='"${yt_video_link_domain}"'/playlist?list=\(.gridPlaylistRenderer.playlistId)"
        }]'
}

_youtube_channel_json() {
	channel_name=$1
	__scr="$2"
	jq '[..|.richGridRenderer?|select(.!=null)|..|.contents?|select(.!=null)|..|.richItemRenderer?|select(.!=null) |
	    {
		scraper: "'"$__scr"'",
	    	ID: .content.videoRenderer.videoId,
		url: "'"$yt_video_link_domain"'/watch?v=\(.content.videoRenderer.videoId)",
		title: .content.videoRenderer.title.runs[0].text,
	    	channel: "'"$channel_name"'",
	    	thumbs: .content.videoRenderer.thumbnail.thumbnails[2].url|sub("\\?.*";""),
	    	duration: .content.videoRenderer.lengthText.simpleText,
            views: "\(.content.videoRenderer.lengthText.simpleText | split("views")[0])",
	    	date: .content.videoRenderer.publishedTimeText.simpleText,
            description: .content.videoRenderer.descriptionSnippet.runs[0].text
	    }
	]'
}
#}}}

scrape_yt () {
    search=$1
    [ "$search" = ":help" ] && print_info "Scrape youtube without invidious\n" && return 100
    output_json_file=$2
    _tmp_html="${session_temp_dir}/yt-search.html"
    _tmp_json="${session_temp_dir}/yt-search.json"

    printf "%s\n" "Scraping Youtube (with https://www.youtube.com) ($search)"

    _get_request "https://www.youtube.com/results" \
		    -G --data-urlencode "search_query=$search" \
		    -H "User-Agent: $4" \
		    -H 'Accept-Language: en-US,en;q=0.9' \
		    --compressed > "$_tmp_html" || exit "$?"
    sed -n '/var *ytInitialData/,$p' < "$_tmp_html" |
	   tr -d '\n' |
	   sed -E ' s_^.*var ytInitialData ?=__ ; s_;</script>.*__ ;' > "$_tmp_json"

    #gets a list of videos
    {
	jq '[ .contents|
	..|.videoRenderer? |
	select(. !=null) |
		{
			scraper: "youtube_search",
			url: "'"${yt_video_link_domain}"'/watch?v=\(.videoId)",
			title: .title.runs[0].text,
			channel: .longBylineText.runs[0].text,
			duration:.lengthText.simpleText,
			views: .shortViewCountText.simpleText,
			date: .publishedTimeText.simpleText,
			description: .detailedMetadataSnippets[0].snippetText.runs[0].text,
			ID: .videoId,
			thumbs: .thumbnail.thumbnails[0].url
		}
	]'

	 jq '[ .contents|
	..|.playlistRenderer? |
	select(. !=null) |
		{
			scraper: "youtube_search",
			url: "'"${yt_video_link_domain}"'/playlist?list=\(.videoId)",
			title: "[Playlist] \(.title.simpleText)",
			channel: .longBylineText.runs[0].text,
			duration: "\(.videoCount) videos",
			views: "playlist",
			date: "playlist",
			ID: .playlistId,
			thumbs: .thumbnails[0].thumbnails[0].url,
			action: "scrape type=invidious-playlist search='"${yt_video_link_domain}"'/playlist?list=\(.playlistId)"
		}
	]'
    } < "$_tmp_json" >> "$output_json_file"
}

scrape_subscriptions() {
	! [ -f "$YTFZF_SUBSCRIPTIONS_FILE" ] && die 2 "subscriptions file doesn't exist${new_line}"

	# if _tmp_subfile does not have a unique name, weird things happen
	__subfile_line=-1
	_start_series_of_threads
	while read -r channel_url || [ -n "$channel_url" ]; do

		__subfile_line=$((__subfile_line + 1))

		channel_url=$(trim_blank "${channel_url%%#*}")

		[ -z "$channel_url" ] && continue
		__subfile_line=$((__subfile_line + 1))
		{
            print_info "Scraping subscription: ${channel_url} (https://www.youtube.com)"
			_tmp_subfile="${session_temp_dir}/channel-$__subfile_line"
            _tmp_html="${session_temp_dir}/${tmp_filename}${__subfile_line}.html"
            _tmp_json="${session_temp_dir}/${tmp_filename}${__subfile_line}.json"
            set_real_channel_url_and_id "$channel_url"
            _get_request "https://www.youtube.com/channel/${channel_id}/videos" > "$_tmp_html"
            _youtube_get_json <"$_tmp_html" > "$_tmp_json"

            channel_name=$(_youtube_channel_name <"$_tmp_html")
			_youtube_channel_json "$channel_name" "youtube_channel_$mod" <"$_tmp_json" >> "$_tmp_subfile"
			__new_data="$(jq '.[].scraper="subscriptions"' <"$_tmp_subfile")"
			printf "%s\n" "$__new_data" >"$_tmp_subfile"
			if [ ${fancy_subs} -eq 1 ]; then
				jq --arg left "${fancy_subs_left}" --arg right "${fancy_subs_right}" '"\($left + .[0].channel + $right)" as $div | [{"title": $div, "action": "do-nothing", "url": $div, "ID": "subscriptions-channel:\(.[0].channel)" }] + .[0:'"$sub_link_count"']' <"$_tmp_subfile"
			else
				jq '.[0:'"$sub_link_count"']' <"$_tmp_subfile"
			fi >>"$ytfzf_video_json_file"
		} &
		_thread_started "$!"
		sleep 0.01
	done <"$YTFZF_SUBSCRIPTIONS_FILE"
	wait
}
scrape_youtube_subscriptions() { scrape_subscriptions "$@"; }
scrape_S() { scrape_subscriptions "$@"; }

scrape_SI() {
	output_json_file="$2"
	_curl_config_file="${session_temp_dir}/curl_config"
	: >"$_curl_config_file"

	while read -r url; do
		url=$(trim_blank "${url%%#*}")

		[ -z "$url" ] && continue

		set_real_channel_url_and_id "$url"

		channel_url="$invidious_instance/api/v1/channels/$channel_id"

		_tmp_file="${session_temp_dir}/SI-${channel_id}.json"

		printf "url=\"%s\"\noutput=\"%s\"\n" "$channel_url" "$_tmp_file" >>"${_curl_config_file}"

	done <"${YTFZF_SUBSCRIPTIONS_FILE}"

	_tmp_json="${session_temp_dir}/SI.json"

	print_info "Scraping subscriptions with instance: $invidious_instance${new_line}"

	curl -fLZ --parallel-max "${max_thread_count}" -K "$_curl_config_file"
	[ $? -eq 2 ] && curl -fL -K "$_curl_config_file"

	set +f
	#this pipeline does the following:
	#   1. concatinate every channel json downloaded (cat)
	#   2. if the json is the newer-style, convert it to a list of videos (jq part 1)
	#   3. if fancy_subs -eq 1
	#   1.  add fancy subs and slice the amount of videos the user wants (jq part 2)
	#   4. else
	#   1.  slice the amount of videos the user wants.
	#   5. convert to ytfzf json format

	_get_invidious_thumb_quality_name

	cat "${session_temp_dir}/SI-"*".json" |
		jq 'if (.videos|type) == "array" then .videos elif (.latestVideos|type) == "array" then .latestVideos else null end' | if [ "$fancy_subs" -eq 1 ]; then
		jq --arg left "${fancy_subs_left}" --arg right "${fancy_subs_right}" '"\($left + .[0].author + $right)" as $div | [{"title": $div, "action": "do-nothing", "url": $div, "ID": "subscriptions-channel:\(.[0].channel)" }] + .[0:'"$sub_link_count"']'
	else
		jq '.[0:'"$sub_link_count"']' | _invidious_search_json_generic "SI"
	fi >>"$output_json_file"
	set -f
}

scrape_youtube_channel() {
	channel_url="$1"
	[ "$channel_url" = ":help" ] && print_info "The search should be a link to a youtube channel${new_line}You can put one or more of the following modifiers followed by a space before the url to specify which type of videos to scrape:${new_line}:videos${new_line}:streams${new_line}:playlists${new_line}:v, :s, and :p may also be used as a shorter version${new_line}You may also use --type=live, --type=video, --type=playlist, or --type=all${new_line}" && return 100
	output_json_file="$2"

	prepare_for_set_args
	#shellcheck disable=2086
	set -- $1
	end_of_set_args
	modifiers=""

	# support the --features=live argument
	case "$search_result_features" in
	*live*) modifiers="streams" ;;
	*video*) modifiers="$modifiers videos" ;;
	*playlist*) modifiers="$modifiers playlists" ;;
	esac

	#support --type=playlist, etc
	prepare_for_set_args ","
	for _type in $search_result_type; do
		case "$_type" in
		all) modifiers="streams playlists videos" ;;
		video) modifiers="$modifiers videos" ;;
		*) modifiers="$modifiers $_type" ;;
		esac
	done
	end_of_set_args

	unset IFS

	for arg in "$@"; do
		case "$arg" in
		:videos | :streams | :playlists) modifiers="$modifiers ${arg#:}" ;; #starts with a colon to have  consistency with the search operator syntax.
		:v) modifiers="$modifiers videos" ;;
		:p) modifiers="$modifiers playlists" ;;
		:s | :l) modifiers="$modifiers streams" ;;
		*)
			channel_url=$arg
			break
			;;
		esac
	done

	modifiers=$(trim_blank "$modifiers")

	[ -z "$modifiers" ] && modifiers="videos"

	set_real_channel_url_and_id "$channel_url"

	for mod in $modifiers; do
		print_info "Scraping Youtube channel: https://www.youtube.com/channel/${channel_id}/$mod${new_line}"
		tmp_filename="channel-${channel_id}-$mod"
		_tmp_html="${session_temp_dir}/${tmp_filename}.html"
		_tmp_json="${session_temp_dir}/${tmp_filename}.json"

		_get_request "https://www.youtube.com/channel/${channel_id}/$mod" >"$_tmp_html"
		_youtube_get_json <"$_tmp_html" >"$_tmp_json"

		channel_name=$(_youtube_channel_name <"$_tmp_html")
		if [ "$mod" = "playlists" ]; then
			_youtube_channel_playlists_json "$channel_name" <"$_tmp_json"
		else
			_youtube_channel_json "$channel_name" "youtube_channel_$mod" <"$_tmp_json"
		fi >>"$output_json_file"
	done
}

# }}}

## Invidious {{{
# invidious backend functions {{{
_get_channel_id() {
	link="$1"
	link="${link##*channel/}"
	link="${link%/*}"
	printf "%s" "$link"
}

_get_invidious_thumb_quality_name() {
	case "$thumbnail_quality" in
	high) thumbnail_quality="hqdefault" ;;
	medium) thumbnail_quality="mqdefault" ;;
	start) thumbnail_quality="1" ;;
	middle) thumbnail_quality="2" ;;
	end) thumbnail_quality="3" ;;
	esac
}

_invidious_search_json_playlist() {
	jq '[ .[] | select(.type=="playlist") |
		{
			scraper: "invidious_search",
			ID: .playlistId,
			url: "'"${yt_video_link_domain}"'/playlist?list=\(.playlistId)",
			title: "[playlist] \(.title)",
			channel: .author,
			thumbs: .playlistThumbnail,
			duration: "\(.videoCount) videos",
			action: "scrape type=invidious-playlist search='"${yt_video_link_domain}"'/playlist?list=\(.playlistId)"
		}
	]'
}
_invidious_search_json_channel() {
	jq '
	[ .[] | select(.type=="channel") |
		{
			scraper: "invidious_search",
			ID: .authorId,
			url: "'"${yt_video_link_domain}"'/channel/\(.authorId)",
			title: "[channel] \(.author)",
			channel: .author,
			thumbs: "https:\(.authorThumbnails[4].url)",
			duration: "\(.videoCount) uploaded videos",
			action: "scrape type=invidious-channel search='"${invidious_instance}"'/channel/\(.authorId)"
		}
	]'
}
_invidious_search_json_live() {
	jq '[ .[] | select(.type=="video" and .liveNow==true) |
		{
			scraper: "invidious_search",
			ID: .videoId,
			url: "'"${yt_video_link_domain}"'/watch?v=\(.videoId)",
			title: "[live] \(.title)",
			channel: .author,
			thumbs: "'"${invidious_instance}"'/vi/\(.videoId)/'"$thumbnail_quality"'.jpg"
		}
	]'
}
_invidious_search_json_videos() {
	__scr="$1"
	jq '
    '"$jq_pad_left"'
		;
	[ .[] | select(.type=="video" and .liveNow==false) |
		{
			scraper: "'"$__scr"'",
			ID: .videoId,
			url: "'"${yt_video_link_domain}"'/watch?v=\(.videoId)",
			title: .title,
			channel: .author,
			thumbs: "'"${invidious_instance}"'/vi/\(.videoId)/'"$thumbnail_quality"'.jpg",
			duration: "\(.lengthSeconds / 60 | floor):\(pad_left(2; .lengthSeconds % 60))",
			views: "\(.viewCount)",
			date: .publishedText,
			description: .description
		}
	]'
}
_invidious_search_json_generic() {
	__scr="$1"
	jq '
    '"$jq_pad_left"'
		;
	[ .[] |
		{
			scraper: "'"$__scr"'",
			ID: .videoId,
			url: "'"${yt_video_link_domain}"'/watch?v=\(.videoId)",
			title: .title,
			channel: .author,
			thumbs: "'"${invidious_instance}"'/vi/\(.videoId)/'"$thumbnail_quality"'.jpg",
			duration: "\(.lengthSeconds / 60 | floor):\(pad_left(2; .lengthSeconds % 60))",
			views: "\(.viewCount)",
			date: .publishedText,
			description: .description
		}
	]'
}

_invidious_playlist_json() {
	jq '
    '"$jq_pad_left"'
		;
	[ .videos | .[] |
		{
			scraper: "invidious_playlist",
			ID: .videoId,
			url: "'"${yt_video_link_domain}"'/watch?v=\(.videoId)",
			title: .title,
			channel: .author,
			thumbs: "'"${invidious_instance}"'/vi/\(.videoId)/'"$thumbnail_quality"'.jpg",
			duration: "\(.lengthSeconds / 60 | floor):\(pad_left(2; .lengthSeconds % 60))",
			date: .publishedText,
			description: .description
		}
	]'
}

_concatinate_json_file() {
	template="$1"
	page_count=$2
	_output_json_file="$3"
	__cur_page=${4:-1}
	set --
	# this sets the arguments to the files in order for cat
	while [ "$__cur_page" -le "$page_count" ]; do
		set -- "$@" "${template}${__cur_page}.json.final"
		__cur_page=$((__cur_page + 1))
	done
	cat "$@" 2>/dev/null >>"$_output_json_file"
}
#}}}

scrape_invidious_playlist() {
	playlist_url=$1
	[ "$playlist_url" = ":help" ] && print_info "The search should be a link to a youtube playlist${new_line}" && return 100
	output_json_file=$2

	playlist_id="${playlist_url##*[?]list=}"

	_get_invidious_thumb_quality_name

	# used to put the full playlist in, to later remove duplicates
	_full_playlist_json="${session_temp_dir}/full-playlist-$playlist_id.json"

	_cur_page=${pages_start:-1}
	pages_to_scrape=${pages_to_scrape:-100}
	pages_start=${pages_start:-1}
	while [ "$_cur_page" -lt "$((pages_start + pages_to_scrape))" ]; do
		_tmp_json="${session_temp_dir}/yt-playlist-$playlist_id-$_cur_page.json"
		_get_request "$invidious_instance/api/v1/playlists/$playlist_id" \
			-G --data-urlencode "page=$_cur_page" >"$_tmp_json" || return "$?"
		jq -e '.videos==[]' <"$_tmp_json" >/dev/null 2>&1 && break
		print_info "Scraping Youtube playlist (with $invidious_instance) (playlist: $playlist_url, pg: $_cur_page)${new_line}"

		_invidious_playlist_json <"$_tmp_json" >>"$output_json_file"
		_cur_page=$((_cur_page + 1))
	done
}
scrape_youtube_playlist() { scrape_invidious_playlist "$@"; }

scrape_invidious_search() {
	page_query=$1
	[ "$page_query" = ":help" ] && print_info "Make a youtube search${new_line}" && return 100
	output_json_file=$2

	_ivs_cur_page=${pages_start:-1}

	page_num=$((_ivs_cur_page + ${pages_to_scrape:-1}))

	# shellcheck disable=SC2209
	case "$search_sort_by" in
	upload_date) search_sort_by="date" ;;
	view_count) search_sort_by=views ;;
	esac

	_start_series_of_threads
	while [ ${_ivs_cur_page} -lt $page_num ]; do
		{
			_tmp_json="${session_temp_dir}/yt-search-$_ivs_cur_page.json"

			print_info "Scraping YouTube (with $invidious_instance) ($page_query, pg: $_ivs_cur_page)${new_line}"

			_get_request "$invidious_instance/api/v1/search" \
				-G --data-urlencode "q=$page_query" \
				--data-urlencode "type=${search_result_type}" \
				--data-urlencode "sort=${search_sort_by}" \
				--data-urlencode "date=${search_upload_date}" \
				--data-urlencode "duration=${search_video_duration}" \
				--data-urlencode "features=${search_result_features}" \
				--data-urlencode "region=${search_region}" \
				--data-urlencode "page=${_ivs_cur_page}" >"$_tmp_json"

			_get_invidious_thumb_quality_name

			{
				_invidious_search_json_live <"$_tmp_json"
				_invidious_search_json_videos "invidious_search" <"$_tmp_json"
				_invidious_search_json_channel <"$_tmp_json"
				_invidious_search_json_playlist <"$_tmp_json"
			} >>"$_tmp_json.final"
		} &
		_ivs_cur_page=$((_ivs_cur_page + 1))
		_thread_started "$!"
	done
	# hangs for some reason when called frrom scrape_new_page_invidious_search
	# probably cause it's a subprocess of ytfzf
	case "$4" in
	1) wait "$!" ;;
	*) wait ;;
	esac
	_concatinate_json_file "${session_temp_dir}/yt-search-" "$((_ivs_cur_page - 1))" "$output_json_file" "$pages_start"
	printf "%s\n" "$_ivs_cur_page" >"${session_temp_dir}/invidious_search-current-page"
}

scrape_youtube() { scrape_invidious_search "$@"; }
scrape_Y() { scrape_invidious_search "$@"; }

scrape_next_page_invidious_search() {
	# we can do this because _comment_file is overritten every time, meaning it will contain the latest scrape
	scrape_invidious_search "$_search" "$video_json_file"
}

scrape_invidious_video_recommended() {
	video="$1"
	[ "$video" = ":help" ] && print_info "The search should be a link to a youtube video${new_line}" && return 100
	output_json_file="$2"
	case "$video" in
	*/*) video="${video##*=}" ;;
	esac
	_tmp_json="${session_temp_dir}/invidious-video-recommended.json"
	_get_request "$invidious_instance/api/v1/videos/$video" | jq '.recommendedVideos' >"$_tmp_json"
	_get_invidious_thumb_quality_name
	_invidious_search_json_generic "invidious_recommended" <"$_tmp_json" >>"$output_json_file"
}
scrape_video_recommended() { scrape_invidious_video_recommended "$@"; }
scrape_R() { scrape_invidious_video_recommended "$@"; }

scrape_invidious_trending() {
	trending_tab=$(title_str "$1")
	[ "$trending_tab" = ":help" ] && print_info "The search should be one of: Normal, Gaming, Music, News${new_line}" && return 100
	output_json_file=$2
	print_info "Scraping YouTube (with $invidious_instance) trending (${trending_tab:-Normal})${new_line}"

	_tmp_json="${session_temp_dir}/yt-trending"

	url="$invidious_instance/api/v1/trending"
	[ -n "$trending_tab" ] && url="${url}?type=${trending_tab}" && _tmp_json="${_tmp_json}-$trending_tab"

	_get_request "$url" \
		-G --data-urlencode "region=${search_region}" >"$_tmp_json" || return "$?"

	_get_invidious_thumb_quality_name

	_invidious_search_json_videos "invidious_trending" <"$_tmp_json" >>"$output_json_file"
}
scrape_youtube_trending() { scrape_invidious_trending "$@"; }
scrape_T() { scrape_invidious_trending "$@"; }

scrape_invidious_channel() {
	channel_url=$1
	[ "$channel_url" = ":help" ] && print_info "The search should be a link to a youtube channel${new_line}You can put one or more of the following modifiers followed by a space before the url to specify which type of videos to scrape:${new_line}:videos${new_line}:streams${new_line}:playlists${new_line}:v, :s, and :p may also be used as a shorter version${new_line}You may also use --type=live, --type=video, --type=playlist, or --type=all${new_line}" && return 100
	output_json_file=$2

	tmp_file_name="channel-${channel_id}"
	_tmp_html="${session_temp_dir}/${tmp_file_name}.html"
	_tmp_json="${session_temp_dir}/${tmp_file_name}.json"

	[ -n "$pages_to_scrape" ] || [ -n "$pages_start" ] && print_warning "If you want to use --pages or --pages-start${new_line}use -c invidious-playlist where the search is https://www.youtube.com/playlist?list=$channel_id${new_line}"

	prepare_for_set_args
	set -- $1
	end_of_set_args

	modifiers=""

	# support the --features=live argument
	case "$search_result_features" in
	*live*) modifiers="streams" ;;
	*video*) modifiers="$modifiers videos" ;;
	*playlist*) modifiers="$modifiers playlists" ;;
	esac

	#support --type=playlist, etc
	prepare_for_set_args ","
	for _type in $search_result_type; do
		case "$_type" in
		all) modifiers="streams playlists videos" ;;
		video) modifiers="$modifiers videos" ;;
		*) modifiers="$modifiers $_type" ;;
		esac
	done
	end_of_set_args
	unset IFS

	for arg in "$@"; do
		case "$arg" in
		:videos | :streams | :playlists) modifiers="$modifiers ${arg#:}" ;; #starts with a colon to have  consistency with the search operator syntax.
		:v) modifiers="$modifiers videos" ;;
		:p) modifiers="$modifiers playlists" ;;
		:s | :l) modifiers="$modifiers streams" ;;
		*)
			channel_url=$arg
			break
			;;
		esac
	done

	modifiers=$(trim_blank "$modifiers")

	[ -z "$modifiers" ] && modifiers="videos"

	# Converting channel title page url to channel video url
	set_real_channel_url_and_id "$channel_url"

	for modifier in $modifiers; do
		channel_url="$invidious_instance/api/v1/channels/$channel_id/$modifier"

		print_info "Scraping Youtube (with $invidious_instance) channel: $channel_url${new_line}"

		case "$modifier" in
			streams)
				__jq_filter='.streams? // []'
				__jq_parser=_invidious_search_json_live
				;;
			playlists)
				__jq_filter='.playlists? // []'
				__jq_parser=_invidious_search_json_playlist
				;;
			videos|*)
				__jq_filter='(.videos? // []) + (.latestVideos? // [])'
				__jq_parser=_invidious_search_json_generic
				;;
		esac

		_get_invidious_thumb_quality_name

		_get_request "${channel_url##* }" \
				-G --data-urlencode "page=$_cur_page" |
			jq "$__jq_filter" | $__jq_parser "invidious_channel" |
			jq 'select(.!=[])' >>"$output_json_file" || return "$?"
	done
}

## }}}

## Ytfzf {{{
scrape_multi() {
	[ "$1" = ":help" ] && print_info "Perform multiple ytfzf calls and present them in 1 menu, a more powerful multi-scrape
Eg:
    ytfzf -cM search 1 :NEXT search 2 :NEXT -c O odysee search :NEXT --pages=3 3 pages of youtube
" && return 100
	PARENT_OUTPUT_JSON_FILE=$2
	PARENT_invidious_instance="$invidious_instance"
	unset IFS
	set -f
	while read -r params; do
		[ -z "$params" ] && continue
		# shellcheck disable=SC2086
		set -- $params
		(
			set_vars 0
			# shellcheck disable=SC2030
			invidious_instance="$PARENT_invidious_instance"
			cache_dir="$session_cache_dir"
			on_opt_parse_s() {
				print_warning "-s is not supported in multi search${new_line}"
			}
			_getopts "$@"
			source_scrapers
			shift $((OPTIND - 1))
			search_again=0
			unset IFS
			init_and_make_search "$*" "fn-args"
			something_was_scraped || exit 4
			cat "$ytfzf_video_json_file" >>"$PARENT_OUTPUT_JSON_FILE"
			clean_up
		)
	done <<-EOF
		    $(printf "%s" "$1" | sed 's/ *:N\(EXT\)* */\n/g')
	EOF
	unset PARENT_invidious_instance PARENT_OUTPUT_JSON_FILE
	return 0
}
scrape_M() { scrape_multi "$@"; }
## }}}

## Peertube {{{
scrape_peertube() {
	page_query=$1
	[ "$page_query" = ":help" ] && print_info "Search peertube${new_line}" && return 100
	output_json_file=$2
	print_info "Scraping Peertube ($page_query)${new_line}"

	_tmp_json="${session_temp_dir}/peertube.json"

	# gets a list of videos
	_get_request "https://sepiasearch.org/api/v1/search/videos" -G --data-urlencode "search=$1" >"$_tmp_json" || return "$?"

	jq '
	def pad_left(n; num):
		num | tostring |
			if (n > length) then ((n - length) * "0") + (.) else . end
		;
	[ .data | .[] |
			{
				scraper: "peertube_search",
				ID: .uuid,
				url: .url,
				title: .name,
				channel: .channel.displayName,
				thumbs: .thumbnailUrl,
				duration: "\(.duration / 60 | floor):\(pad_left(2; .duration % 60))",
				views: "\(.views)",
				date: .publishedAt
			}
		]' <"$_tmp_json" >>"$output_json_file"

}
scrape_P() { scrape_peertube "$@"; }
## }}}

## Odysee {{{
scrape_odysee() {
	[ "$odysee_video_search_count" -gt 50 ] && die 1 "--odysee-video-count must be <= 50"
	page_query=$1
	[ "$page_query" = ":help" ] && print_info "Search odysee${new_line}" && return 100
	[ "${#page_query}" -le 2 ] && die 4 "Odysee searches must be 3 or more characters${new_line}"
	output_json_file=$2

	# for scrape_next_page_odysee_search
	[ -z "$_initial_odysee_video_search_count" ] && _initial_odysee_video_search_count=$odysee_video_search_count

	print_info "Scraping Odysee ($page_query)${new_line}"

	_tmp_json="${session_temp_dir}/odysee.json"

	case "$search_sort_by" in
	upload_date | newest_first) search_sort_by="release_time" ;;
	oldest_first) search_sort_by="^release_time" ;;
	relevance) search_sort_by="" ;;
	esac
	case "$search_upload_date" in
	week | month | year) search_upload_date="this${search_upload_date}" ;;
	day) search_upload_date="today" ;;
	esac

	case "$nsfw" in
	1) nsfw=true ;;
	0) nsfw=false ;;
	esac

	# this if is because when search_sort_by is empty, it breaks lighthouse
	if [ -n "$search_sort_by" ]; then
		_get_request "https://lighthouse.lbry.com/search" -G \
			--data-urlencode "s=$page_query" \
			--data-urlencode "mediaType=video,audio" \
			--data-urlencode "include=channel,title,thumbnail_url,duration,cq_created_at,description,view_cnt" \
			--data-urlencode "sort_by=$search_sort_by" \
			--data-urlencode "time_filter=$search_upload_date" \
			--data-urlencode "nsfw=$nsfw" \
			--data-urlencode "size=$odysee_video_search_count" >"$_tmp_json" || return "$?"
	else
		_get_request "https://lighthouse.lbry.com/search" -G \
			--data-urlencode "s=$page_query" \
			--data-urlencode "mediaType=video,audio" \
			--data-urlencode "include=channel,title,thumbnail_url,duration,cq_created_at,description,view_cnt" \
			--data-urlencode "time_filter=$search_upload_date" \
			--data-urlencode "nsfw=$nsfw" \
			--data-urlencode "size=$odysee_video_search_count" >"$_tmp_json" || return "$?"

	fi
	# select(.duration != null) selects videos that aren't live, there is no .is_live key
	jq '
	def pad_left(n; num):
		num | tostring |
			if (n > length) then ((n - length) * "0") + (.) else . end
		;
	[ .[] |select(.duration != null) |
	    {
		    scraper: "odysee_search",
			ID: .claimId,
			title: .title,
			url: "https://www.odysee.com/\(.channel)/\(.name)",
			channel: .channel,
			thumbs: .thumbnail_url,
			duration: "\(.duration / 60 | floor):\(pad_left(2; .duration % 60))",
			views: "\(.view_cnt)",
			date: .cq_created_at
	    }
	]' <"$_tmp_json" >>"$output_json_file"

}
scrape_O() { scrape_odysee "$@"; }
## }}}

# ytfzf json format{{{

scrape_from_cache () {
    search="$1"
    [ "$search" = ":help" ] && print_info "Scrapes from a cached ytfzf search${new_line}the search is the cache # to use, where 1 is the most recent and \$ is the least recent" && return 100
    on_clean_up_scrape_from_cache () {
        rm -r "${cache_dir}/${SEARCH_PREFIX}-${YTFZF_PID}" > /dev/null 2>&1
    }
    load_fake_extension "scrape_from_cache"

    set +f
    _locations=$(
        for location in "$cache_dir"/*-[0-9][0-9]*; do
            printf "%s\n" "$(cat "${location}/created-at")-${location}"
        done | sort -nr | cut -d '-' -f2-
    )

    if [ -n "$search" ]; then
        _location="$(sed -n "${search}p" <<EOF
$_locations
EOF
)"
    else
        _location=$(quick_menu_wrapper "Pick from previous searches" <<EOF
$_locations
EOF
)
    fi
    [ -z "$_location" ] && return 1
    scrape_json_file "$_location/videos_json" "$2"
    cp -r "$_location/thumbnails" "${session_cache_dir}"
    set -f
}

scrape_json_file() {
	search="$1"
	output_json_file="$2"
	cp "$search" "$output_json_file" 2>/dev/null
}
scrape_playlist() { scrape_json_file "$@"; }
scrape_p() { scrape_json_file "$@"; }
#}}}

# Comments{{{
scrape_comments() {
	video_id="$1"
	[ "$video_id" = ":help" ] && print_info "Search should be a link to a youtube video${new_line}" && return 100
	case "$video_id" in
	*/*) video_id="${video_id##*=}" ;;
	esac
	output_json_file="$2"
	_comment_file="${session_temp_dir}/comments-$video_id.tmp.json"
	i="${pages_start:-1}"
	page_count="$((i + ${pages_to_scrape:-1}))"
	while [ "$i" -le "$page_count" ]; do
		print_info "Scraping comments (pg: $i)${new_line}"
		_out_comment_file="${session_temp_dir}/comments-$i.json.final"
		_get_request "$invidious_instance/api/v1/comments/${video_id}" -G \
			--data-urlencode "continuation=$continuation" >"$_comment_file"
		continuation=$(jq -r '.continuation' <"$_comment_file")
		jq --arg continuation "$continuation" '[ .comments[] | {"scraper": "comments", "channel": .author, "date": .publishedText, "ID": .commentId, "title": .author, "description": .content, "url": "'"$yt_video_link_domain"'/watch?v='"$video_id"'&lc=\(.commentId)", "action": "do-nothing", "thumbs": .authorThumbnails[2].url, "continuation": $continuation} ]' <"$_comment_file" >>"$output_json_file"
		i=$((i + 1))
	done
	printf "%s\n" "$i" >"${session_temp_dir}/comments-current-page"
}

scrape_next_page_comments() {
	# we can do this because _comment_file is overritten every time, meaning it will contain the latest scrape
	scrape_comments "$_search" "$video_json_file"
}
#}}}

# url {{{
scrape_url() {
	printf "%s\n" "$1" >"$ytfzf_selected_urls"
	open_format_selection_if_requested "$ytfzf_selected_urls"
	open_url_handler "$ytfzf_selected_urls"
	close_url_handler "$url_handler"
	exit
}
scrape_U() { scrape_url "$@"; }
scrape_u() { printf '[{"ID": "%s", "title": "%s", "url": "%s"}]\n' "URL-${1##*/}" "$1" "$1" >>"$2"; }
#}}}

# }}}

# Sorting {{{

############################
#         SORTING          #
############################

# There is a 2 step soring process.
# 1. the get_sort_by function is called
# 2. the data_sort_fn function is called
# The result of those 2 steps is then printed to stdout.

#TODO: refactor sorting to not rely on video_info_text, and instead be based on json

# Take a json line as the first argument, the line should follow VIDEO JSON FORMAT
# This function should print the information from the line to sort by (or something else)
# This specific implementation of get_sort_by prints the upload date in unix time
command_exists "get_sort_by" || get_sort_by() {
	_video_json_line="$1"
	date="${_video_json_line##*'"date":"'}"
	date="${date%%\"*}"
	# youtube specific
	date=${date#*Streamed}
	date=${date#*Premiered}
	date -d "$date" '+%s' 2>/dev/null || date -f "$date" '+%s' 2>/dev/null || printf "null"
}

# This function sorts the data being piped into it.
command_exists "data_sort_fn" || data_sort_fn() {
	sort -nr
}

#This function reads all lines being piped in, and sorts them.
sort_video_data_fn() {
	if [ $is_sort -eq 1 ]; then
		while IFS= read -r _video_json_line; do
			# run the key function to get the value to sort by
			get_sort_by "$_video_json_line" | tr -d '\n'
			printf "\t%s\n" "$_video_json_line"
		done | data_sort_fn | cut -f2-
	else
		cat
	fi
}
#}}}

# History Management {{{

#}}}

# User Interface {{{

############################
#        INTERFACES        #
############################

# The interface takes 2 arguments
# 1: The video json file to read from
# The json file will be in the VIDEO JSON FORMAT (see ytfzf(5)) for more information
# 2: The url file to write to
# each url should be seperated by a new line when written to the url file.

# Interfaces are responsible for the following:

# $ytfzf_video_json_file contains a file with the raw search result json
# or use the create_sorted_video_data to get a jsonl string of sorted videos.

# * Checking if the menu it wants to use is installed.
# * Example: interface_text checks if fzf is installed and exits with code 3 if it can't.

# * If the interface uses shortcuts, it is responsible for calling handle_post_keypress if the $keypress_file exists.

# * The interface should display thumbnails if thumbnails are enabled, and the interface supports it

# * It is not required, but interfaces (especially tui interfaces) should use the output from the output from the video_info_text function to display the results.
# * The interface needs to define the following variables for video_info_text to work properly:
# * title_len
# * channel_len
# * dur_len
# * view_len
# * date_len
# Each of these variables should equal the amount of columns (characters) each segment should take

# * Lastly, if a key, or key combination was pressed (and the interface supports it), it should be written to $keypress_file.
# * $keypress_file will be used *after* the interface is closed, If the interface does not function in a way similar to fzf do not use this file for shortcuts.
# * When handling keypresses manually, it is preferrable to use the keybinds listed in $shortcut_binds,
# * For example, the download shortcut to check against should be $download_shortcut

# Keypresses {{{
set_keypress() {
	# this function uses echo to keep new lines
	read -r keypress
	while read -r line; do
		input="${input}${new_line}${line}"
	done
	# this if statement checks if there is a keypress, if so, print the input, otherwise print everything
	# $keypress could also be a standalone variable, but it's nice to be able to interact with it externally
	if printf "%s" "$keypress" | grep -E '^[[:alnum:]-]+$' >"$keypress_file"; then
		echo "$input" | sed -n '2,$p'
	else
		# there was no key press, remove all blank lines
		echo "${keypress}${new_line}${input}" | grep -Ev '^[[:space:]]*$'
	fi
	unset keypress
}

handle_post_keypress() {
	read -r keypress <"$keypress_file"
	command_exists "handle_custom_post_keypresses" && { handle_custom_post_keypresses "$keypress" || return "$?"; }
	case "$keypress" in
	"$download_shortcut" | "$video_shortcut" | "$audio_shortcut") url_handler=$_last_url_handler ;;
	"$detach_shortcut") is_detach=0 ;;
	"$print_link_shortcut" | "$info_shortcut") info_to_print="$_last_info_to_print" ;;
	"$show_formats_shortcut") show_formats=0 ;;
	"$search_again_shortcut") : ;;
	*)
		_fn_name=handle_post_keypress_$(
			sed 's/-/_/g' <<-EOF
				$keypress
			EOF
		)
		command_exists "$_fn_name" && $_fn_name
		;;
	esac
	unset keypress

}

handle_keypress() {
	read -r keypress <"$1"

	print_debug "[KEYPRESS]: handling keypress: $keypress${new_line}"

	command_exists "handle_custom_keypresses" && { handle_custom_keypresses "$keypress" || return "$?"; }
	case "$keypress" in
	"$download_shortcut")
		_last_url_handler=$url_handler
		url_handler=downloader
		;;
	"$video_shortcut")
		_last_url_handler=$url_handler
		url_handler=video_player
		;;
	"$audio_shortcut")
		_last_url_handler=$url_handler
		url_handler=audio_player
		;;
	"$detach_shortcut") is_detach=1 ;;
	"$print_link_shortcut")
		_last_info_to_print="$info_to_print"
		info_to_print="L"
		;;
	"$show_formats_shortcut") show_formats=1 ;;
	"$info_shortcut")
		_last_info_to_print="$info_to_print"
		info_to_print="VJ"
		;;
	"$search_again_shortcut")
		clean_up
		initial_search="" init_and_make_search "" "$search_source"
		return 3
		;;
	*)
		_fn_name=handle_keypress_$(
			sed 's/-/_/g' <<-EOF
				$keypress
			EOF
		)
		command_exists "$_fn_name" && $_fn_name
		rv="$?"
		;;
	esac
	unset keypress
	return "${rv:-0}"
}

#}}}

command_exists "thumbnail_video_info_text_comments" || thumbnail_video_info_text_comments() {
	[ -n "$title" ] && printf "${c_bold}%s\n${c_reset}" "$title"
	[ -n "$description" ] && printf "\n%s" "$description"
}

# Scripting selection {{{
auto_select() {
	video_json_file=$1
	selected_id_file=$2
	# shellcheck disable=SC2194
	case 1 in
	#sed is faster than jq, lets use it
	#this sed command finds `"url": "some-url"`, and prints all urls then selects the first $scripting_video_count urls.
	"$is_auto_select") sed -n 's/[[:space:]]*"url":[[:space:]]*"\([^"]\+\)",*$/\1/p' <"$video_json_file" | sed -n "1,${scripting_video_count}p" ;;
	"$is_random_select") sed -n 's/[[:space:]]*"url":[[:space:]]*"\([^"]\+\)",*$/\1/p' <"$video_json_file" | shuf | sed -n "1,$scripting_video_count"p ;;
	"$is_specific_select") jq -r '.[]|"\(.title)\t|\(.channel)\t|\(.duration)\t|\(.views)\t|\(.date)\t|\(.viewed)\t|\(.url)"' <"$ytfzf_video_json_file" | sed -n "$scripting_video_count"p | trim_url ;;
	*) return 1 ;;
	esac >"$selected_id_file"
	return 0
	# jq '.[]' < "$video_json_file" | jq -s -r --arg N "$scripting_video_count" '.[0:$N|tonumber]|.[]|.ID' > "$selected_id_file"
}
# }}}

# Text interface {{{
interface_text() {
	command_exists "fzf" || die 3 "fzf not installed, cannot use the default menu${new_line}"
	# if it doesn't exist, this menu has not opened yet, no need to revert the actions of the last keypress
	[ -f "$keypress_file" ] && handle_post_keypress

	_fzf_start_bind=""
	if [ "${_const_fzf_selected_line_no:-0}" -gt 0 ]; then
		#if line n (where n != 0) was selected, add a start bind that moves the cursor down (n) times
		_fzf_start_bind="--bind start:$(mul_str "down+" "${_const_fzf_selected_line_no}")"
		_fzf_start_bind="${_fzf_start_bind%"+"}"
	fi

	[ "$show_thumbnails" -eq 1 ] && {
		interface_thumbnails "$@"
		return
	}

	video_json_file=$1
	selected_id_file=$2

	_init_video_info_text "$TTY_COLS"

	unset IFS

	_c_SORTED_VIDEO_DATA="$(create_sorted_video_data)"

	printf "%s\n" "$_c_SORTED_VIDEO_DATA" |
		video_info_text |
		_post_video_info_text |
		fzf -m --sync --tabstop=1 --layout=reverse --expect="$shortcut_binds" \
			$_fzf_start_bind \
			--bind "${next_page_action_shortcut}:reload(__is_fzf_preview=1 TTY_COLS=${TTY_COLS} TTY_LINES=${TTY_LINES} YTFZF_CHECK_VARS_EXISTS=1 session_cache_dir='$session_cache_dir' ytfzf_video_json_file='$ytfzf_video_json_file' invidious_instance='$invidious_instance' yt_video_link_domain='$yt_video_link_domain' pages_to_scrape='$pages_to_scrape' session_temp_dir='$session_temp_dir' $0 -W \"next_page"$EOT"{f}\")" | set_keypress |
		trim_url >"$selected_id_file"

	_const_top_url="$(head -n 1 "$selected_id_file")"
	_const_fzf_selected_line_no="$(
		jq -s -r --arg url "$_const_top_url" 'flatten|[.[]|.url]|index($url)' <<-EOF
			    ${_c_SORTED_VIDEO_DATA}
		EOF
	)"
}
#}}}

# External interface {{{
interface_ext() {
	video_json_file=$1
	selected_id_file=$2

	# video_info_text can be set in the conf.sh, if set it will be preferred over the default given below
	_init_video_info_text $external_menu_len

	create_sorted_video_data |
		video_info_text |
		external_menu "Select video: " |
		trim_url >"$selected_id_file"
}
#}}}

# Thumbnail Interface {{{

_get_video_json_attr() {
	sed -n 's/^[[:space:]]*"'"$1"'":[[:space:]]*"\([^\n]*\)",*/\1/p' <<-EOF | sed 's/\\\([\\"]\)/\1/g'
		    $_correct_json
	EOF
}

# Image preview {{{
preview_start() {
	thumbnail_viewer=$1
	case $thumbnail_viewer in
	ueberzug | sixel | kitty | iterm2 | sway | wayland)
		command_exists "ueberzug" || {
			[ "$thumbnail_viewer" = "ueberzug" ] && die 3 "ueberzug is not installed${new_line}" || die 3 "ueberzugpp is not installed${new_line}"
		}
		export UEBERZUG_FIFO="$session_temp_dir/ytfzf-ueberzug-fifo"
		rm -f "$UEBERZUG_FIFO"
		mkfifo "$UEBERZUG_FIFO"
        if [ "$thumbnail_viewer" = "ueberzug" ]; then
            o="x11"
        else
             o="${thumbnail_viewer}"
        fi
		if command_exists ueberzugpp; then
			ueberzugpp layer -o "${o}" --parser json <"$UEBERZUG_FIFO" 2>>"$thumbnail_debug_log" &
		else
			ueberzug layer --parser json <"$UEBERZUG_FIFO" 2>>"$thumbnail_debug_log" &
		fi
		exec 3>"$UEBERZUG_FIFO"
		;;
	chafa | chafa-16 | chafa-tty | catimg | catimg-256 | swayimg | swayimg-hyprland) : ;;
	imv)
		first_img="$(jq -r '.[0].ID|select(.!=null)' <"$ytfzf_video_json_file")"
		imv "$thumb_dir/${first_img}.jpg" >>"$thumbnail_debug_log" 2>&1 &
		export imv_pid="$!"
		# helps prevent imv seg fault
		sleep 0.1
		;;
	mpv)
		command_exists "socat" && command_exists "mpv" || die 3 "socat, and mpv must be installed for the mpv thumbnail viewer"
		first_img="$(jq -r '.[0].ID|select(.!=null)' <"$ytfzf_video_json_file")"
		export MPV_SOCKET="$session_temp_dir/mpv.socket"
		rm -f "$MPV_SOCKET" >/dev/null 2>&1
		mpv --input-ipc-server="$MPV_SOCKET" --loop-file=inf --idle=yes "$thumb_dir/${first_img}.jpg" >>"$thumbnail_debug_log" 2>&1 &
		export mpv_pid=$!
		;;
	*)
		"$thumbnail_viewer" "start" "$FZF_PREVIEW_COLUMNS" "$FZF_PREVIEW_LINES" 2>/dev/null
		;;
	esac
}
preview_stop() {
	thumbnail_viewer=$1
	case $thumbnail_viewer in
	ueberzug | sixel | kitty | iterm2 | sway | wayland) exec 3>&- ;;
	chafa | chafa-16 | chafa-tty | catimg | catimg-256) : ;;
	mpv)
		kill "$mpv_pid"
		rm "$MPV_SOCKET" >/dev/null 2>&1
		;;
	swayimg | swayimg-hyprland) killall swayimg 2>/dev/null ;;
	imv) kill "$imv_pid" ;;
	*)
		"$thumbnail_viewer" "stop" "$FZF_PREVIEW_COLUMNS" "$FZF_PREVIEW_LINES" 2>/dev/null
		;;
	esac
}

command_exists "on_no_thumbnail" || on_no_thumbnail() {
	die 1 "No image${new_line}"
}

preview_no_img() {
	thumbnail_viewer="$1"
	case $thumbnail_viewer in
	chafa | chafa-16 | chafa-tty | catimg | catimg-256 | imv | mpv) : ;;
	ueberzug | sixel | kitty | iterm2 | sway | wayland)
		{
			printf "{"
			printf "\"%s\": \"%s\"," "action" "remove" "identifier" "ytfzf"
			printf '"%s": "%s"' "draw" "True"
			printf "}\n"
		} >"$UEBERZUG_FIFO"
		;;
	swayimg | swayimg-hyprland)
		killall swayimg 2>/dev/null
		true
		;; # we want this to be true so that the && at the bottom happens
	*) "$thumbnail_viewer" "no-img" ;;
	esac && do_an_event_function "on_no_thumbnail"

}
# ueberzug positioning{{{
command_exists "get_ueberzug_positioning_left" || get_ueberzug_positioning_left() {
	width=$1
	height=$(($2 - __text_line_count + 2))
	x=2
	y=$((__text_line_count + 2))
}
command_exists "get_ueberzug_positioning_right" || get_ueberzug_positioning_right() {
	get_ueberzug_positioning_left "$@"
	width=$1
	x=$(($1 + 6))
}
command_exists "get_ueberzug_positioning_up" || get_ueberzug_positioning_up() {
	width=$1
	height=$(($2 - __text_line_count))
	x=2
	y=9
}
command_exists "get_ueberzug_positioning_down" || get_ueberzug_positioning_down() {
	width=$1
	height=$(($2 - __text_line_count))
	#$2*2 goes to the bottom subtracts height, adds padding
	y=$(($2 * 2 - height + 2))
	x=2
}

command_exists "get_swayimg_positioning_left" || get_swayimg_positioning_left() {
	# allows space for text
	y_gap=$((__text_line_count + 3)) #the plus 3 just seems to work better
	y_gap=$((line_px_height * y_gap))
	#these are seperate because treesitter syntax highlighting dies when parentheses are inside of math

	# it's subtracting the gap between the border and the edge of terminal
	w_correct=$((max_width / 2 - 2 * col_px_width))
	h_correct=$((max_height - 3 * line_px_height - y_gap))

	# offset from the edge by half a column
	x=$((term_x + col_px_width / 2))
	# move down to allow for text
	y=$((term_y + y_gap))
	[ "$img_w" -gt "$w_correct" ] && img_w=$((w_correct))
	#-20 is to leave space for the text
	[ "$img_h" -gt "$h_correct" ] && img_h=$((h_correct))
}

command_exists "get_swayimg_positioning_right" || get_swayimg_positioning_right() {
	get_swayimg_positioning_left "$@"
	# after setting the positioning as if side was `left` set x to the correct place
	x=$((term_x + max_width - w_correct))
}

command_exists "get_swayimg_positioning_up" || get_swayimg_positioning_up() {
	w_correct=$((max_width / 2))
	# offset from border slightly
	h_correct=$((max_height - 2 * line_px_height))

	# offset from info text by 30 columns
	x=$((max_width - w_correct))
	x=$((term_x + x))
	# go down from the top by 2 lines
	y=$((term_y + 2 * line_px_height))

	[ "$img_w" -gt "$w_correct" ] && img_w=$((w_correct))
	#-20 is to leave space for the text
	[ "$img_h" -gt "$h_correct" ] && img_h=$((h_correct))
}

command_exists "get_swayimg_positioning_down" || get_swayimg_positioning_down() {
	get_swayimg_positioning_up "$@"
	# after setting the positioning as if side was `up` set y to the correct place
	y=$((term_y + max_height / 2 + 2 * line_px_height))
}

get_swayimg_positioning() {
	max_width=$1
	max_height=$2
	term_x=$3
	term_y=$4
	col_px_width=$5
	line_px_height=$6

	img_size="$(identify -format "%w %h" "$thumb_path")"
	img_w=${img_size% *}
	img_h=${img_size#* }

	get_swayimg_positioning_$fzf_preview_side "${img_size% *}" "${img_size#* }" "$max_width" "$max_height" "$term_x" "$term_y" "$col_px_width" "$line_px_height"
}

get_ueberzug_positioning() {
	max_width=$1
	max_height=$2
	"get_ueberzug_positioning_$fzf_preview_side" "$max_width" "$max_height"
}
#}}}
preview_display_image() {
	thumbnail_viewer=$1
	id=$2

	for path in "${YTFZF_CUSTOM_THUMBNAILS_DIR}/$id.jpg" "${thumb_dir}/${id}.jpg" "${YTFZF_CUSTOM_THUMBNAILS_DIR}/YTFZF:DEFAULT.jpg"; do
		thumb_path="$path"
		[ -f "${thumb_path}" ] && break
	done || preview_no_img "$thumbnail_viewer"
	# this is separate becuase, preview_no_img will not happen if thumb_path = YTFZF:DEFAULT, but on_no_thumbnail should still happen
	[ "$thumb_path" = "${YTFZF_CUSTOM_THUMBNAILS_DIR}/YTFZF:DEFAULT.jpg" ] && do_an_event_function "on_no_thumbnail"

	get_ueberzug_positioning "$FZF_PREVIEW_COLUMNS" "$FZF_PREVIEW_LINES" "$fzf_preview_side"
	case $thumbnail_viewer in
	ueberzug | sixel | kitty | iterm2 | sway | wayland)
		{
			printf "{"
			printf '"%s": "%s",' \
				'action' 'add' \
				'identifier' 'ytfzf' \
				'path' "$thumb_path" \
				'x' "$x" \
				'y' "$y" \
				'width' "$width"
			printf '"%s": "%s"' 'height' "$height"
			printf "}\n"
		} >"$UEBERZUG_FIFO" 2>>"$thumbnail_debug_log"
		;;
	swayimg-hyprland)
		command_exists "hyprctl" || die 3 "hyprctl is required for this thumbnail viewer${new_line}"
		_swayimg_pid_file="${session_temp_dir}/_swayimg.pid"
		[ -f "$_swayimg_pid_file" ] && kill "$(cat "$_swayimg_pid_file")" 2>/dev/null

		window_data="$(hyprctl activewindow -j)"

		IFS=" " read -r x y w h <<-EOF
			            $(printf "%s" "$window_data" | jq -r '"\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"')
		EOF
		read -r output_x output_y <<-EOF
			            $(hyprctl monitors -j | jq -r '.[]|select(.focused==true) as $mon | "\($mon.x) \($mon.y)"')
		EOF
		x=$((x - output_x))
		y=$((y - output_y))
		# shellcheck disable=SC2034
		w_half=$((w / 2)) h_half=$((h / 2))
		# how many pixels per col
		col_px_width=$((w / TTY_COLS))
		# how many pixels per line
		line_px_height=$((h / TTY_LINES))
		get_swayimg_positioning "$((w))" "$((h))" "$x" "$y" "$col_px_width" "$line_px_height"
		hyprctl keyword windowrulev2 "move $((x + 10)) $y,title:swayimg" >/dev/null 2>&1
		hyprctl keyword windowrulev2 float,title:swayimg >/dev/null 2>&1
		hyprctl keyword windowrulev2 nofocus,title:swayimg >/dev/null 2>&1
		hyprctl keyword windowrulev2 "noborder,title:swayimg" >/dev/null 2>&1
		swayimg -s fit -g $((x + 10)),$y,$((img_w)),$((img_h)) "$thumb_path" 2>>"$thumbnail_debug_log" >&2 &
		printf "%s" "$!" >"$_swayimg_pid_file"
		# without this there are weird flushing issues (maybe)
		;;
	swayimg)
		_swayimg_pid_file="${session_temp_dir}/_swayimg.pid"
		[ -f "$_swayimg_pid_file" ] && kill "$(cat "$_swayimg_pid_file")" 2>/dev/null
		# this jq call finds the id of the selected monitor and saves it as $focused_id
		# then finds x, and y of the focused monitor and saves it as the var $d1
		# then it finds the geometry of the focused window and saves it as the var $d2
		# at the end it concatinates the two strings with a tab in the middle so that read can read it into 6 vars
		read -r output_x output_y x y w h <<-EOF
			    $(swaymsg -t get_tree | jq -r '. as $data |
			        .focus[0] as $focused_id |
			        ..| try select(.type=="output" and .id==$focused_id) |
			        [.rect.x,.rect.y] | @tsv as $d1 |
			        $data | .. | try select(.focused==true) |
			        [.rect.x,.rect.y,.rect.width,.rect.height] | @tsv as $d2 |
			        $d1 + "\t" + $d2')
		EOF
		# we're subtracting output_* to make sure swayimg places on correct monitor
		x=$((x - output_x))
		y=$((y - output_y))
		# shellcheck disable=SC2034
		w_half=$((w / 2)) h_half=$((h / 2))
		# how many pixels per col
		col_px_width=$((w / TTY_COLS))
		# how many pixels per line
		line_px_height=$((h / TTY_LINES))
		get_swayimg_positioning "$((w))" "$((h))" "$x" "$y" "$col_px_width" "$line_px_height"
		swaymsg 'no_focus [app_id="swayimg_.*"]' >/dev/null 2>&1
		swayimg -s fit -g $x,$y,$((img_w)),$((img_h)) "$thumb_path" 2>>"$thumbnail_debug_log" >&2 &
		printf "%s" "$!" >"$_swayimg_pid_file"
		# without this there are weird flushing issues (maybe)
		echo
		;;
	chafa)
		printf '\n'
		command_exists "chafa" || die 3 "${new_line}chafa is not installed${new_line}"
		chafa --format=symbols -s "$((width - 4))x$height" "$thumb_path" 2>>"$thumbnail_debug_log"
		;;
	chafa-16)
		printf '\n'
		command_exists "chafa" || die 3 "${new_line}chafa is not installed${new_line}"
		chafa --format=symbols -c 240 -s "$((width - 2))x$((height - 10))" "$thumb_path" 2>>"$thumbnail_debug_log"
		;;
	chafa-tty)
		printf '\n'
		command_exists "chafa" || die 3 "${new_line}chafa is not installed${new_line}"
		chafa --format=symbols -c 16 -s "$((width - 2))x$((height - 10))" "$thumb_path"  2>>"$thumbnail_debug_log"
		;;
	catimg)
		printf '\n'
		command_exists "catimg" || die 3 "${new_line}catimg is not installed${new_line}"
		catimg -w "$width" "$thumb_path" 2>>"$thumbnail_debug_log"
		;;
	catimg-256)
		printf '\n'
		command_exists "catimg" || die 3 "${new_line}catimg is not installed${new_line}"
		catimg -c -w "$width" "$thumb_path" 2>>"$thumbnail_debug_log"
		;;
	imv)
		imv-msg "$imv_pid" open "$thumb_path" 2>>"$thumbnail_debug_log" >&2
		imv-msg "$imv_pid" next 2>>"$thumbnail_debug_log" >&2
		;;
	mpv)
		echo "loadfile '$thumb_path'" | socat - "$MPV_SOCKET" >>"$thumbnail_debug_log" 2>&1
		;;
	*)
		get_ueberzug_positioning "$FZF_PREVIEW_COLUMNS" "$FZF_PREVIEW_LINES" "$fzf_preview_side"
		"$thumbnail_viewer" "view" "$thumb_path" "$x" "$y" "$width" "$height" "$FZF_PREVIEW_COLUMNS" "$FZF_PREVIEW_LINES" "$fzf_preview_side"
		;;

	esac
}
#}}}

preview_img() {
	# This function is common to every thumbnail viewer
	thumbnail_viewer=$1
	line=$2
	video_json_file=$3
	url=${line##*"|"}

	# make sure all variables are set{{{
	_correct_json=$(jq -nr --arg url "$url" '[inputs[]|select(.url==$url)][0]' <"$video_json_file")
	id="$(_get_video_json_attr "ID")"
	title="$(_get_video_json_attr "title")"
	channel="$(_get_video_json_attr "channel")"
	views="$(_get_video_json_attr "views")"
	date="$(_get_video_json_attr "date")"
	scraper="$(_get_video_json_attr "scraper")"
	duration="$(_get_video_json_attr "duration")"
	viewed="$(_get_video_json_attr "viewed")"
	description="$(_get_video_json_attr "description" | sed 's/\\n/\n/g')"
	#}}}

	_const_text=$(if command_exists "thumbnail_video_info_text${scraper:+_$scraper}"; then
		thumbnail_video_info_text${scraper:+_$scraper}
	else
		thumbnail_video_info_text
	fi)

	__text_line_count=$(
		wc -l <<-EOF
			    $_const_text
		EOF
	)

	echo "$_const_text"

	preview_display_image "$thumbnail_viewer" "$id"
}

interface_thumbnails() {
	# Takes video json file and downloads the thumnails as ${ID}.png to thumb_dir
	video_json_file=$1
	selected_id_file=$2

	preview_start "$thumbnail_viewer"

	unset IFS

	# ytfzf -U preview_img ueberzug {} "$video_json_file"
	# fzf_preview_side will get reset if we don't pass it in

	_c_SORTED_VIDEO_DATA="$(create_sorted_video_data)"

	YTFZF_SERVER_PID="$!"

	printf "%s\n" "$_c_SORTED_VIDEO_DATA" |
		jq -r '"\(.title)'"$gap_space"'\t|\(.channel)\t|\(.duration)\t|\(.views)\t|\(.date)\t|\(.viewed)\t|\(.url)"' |
		SHELL="$(command -v sh)" fzf -m --sync \
			--expect="$shortcut_binds" \
			--preview "__is_fzf_preview=1 YTFZF_CHECK_VARS_EXISTS=1 session_cache_dir='$session_cache_dir' session_temp_dir='$session_temp_dir' fzf_preview_side='$fzf_preview_side' scrape='$scrape' thumbnail_viewer='$thumbnail_viewer' ytfzf_video_json_file='$ytfzf_video_json_file' $0 -W \"preview_img"$EOT"{f}\"" \
			$_fzf_start_bind \
			--bind "${next_page_action_shortcut}:reload(__is_fzf_preview=1 TTY_COLS=${TTY_COLS} TTY_LINES=${TTY_LINES} YTFZF_CHECK_VARS_EXISTS=1 session_cache_dir='$session_cache_dir' ytfzf_video_json_file='$ytfzf_video_json_file' invidious_instance='$invidious_instance' yt_video_link_domain='$yt_video_link_domain' pages_to_scrape='$pages_to_scrape' session_temp_dir='$session_temp_dir' $0 -W \"next_page"$EOT"{f}\")" \
			--preview-window "$fzf_preview_side:50%:wrap" --layout=reverse | set_keypress |
		trim_url >"$selected_id_file"

	preview_stop "$thumbnail_viewer"

	_const_top_url="$(head -n 1 "$selected_id_file")"
	_const_fzf_selected_line_no="$(
		jq -s -r --arg url "$_const_top_url" 'flatten|[.[]|.url]|index($url)' <<-EOF
			    $_c_SORTED_VIDEO_DATA
		EOF
	)"
}
#}}}

#}}}

# Handling selection from interface {{{
get_requested_info() {
	url_list="$1"
	prepare_for_set_args ","
	set -- $info_to_print
	urls="[$(sed 's/^\(.*\)$/"\1",/' "$url_list")"
	urls="${urls%,}]"
	for request in "$@"; do
		case "$request" in
		[Ll] | link)
			# cat is better here because a lot of urls could be selected
			cat "$url_list"
			;;
		VJ | vj | video-json) jq '(.[] | if( [.url] | inside('"$urls"')) then . else "" end)' <"$ytfzf_video_json_file" | jq -s '[ .[]|select(.!="") ]' ;;
		[Jj] | json) jq <"$ytfzf_video_json_file" ;;
		[Ff] | format) printf "%s\n" "$ytdl_pref" ;;
		[Rr] | raw)
			jq -r '.[] | if( [.url] | inside('"$urls"')) then "\(.title)\t|\(.channel)\t|\(.duration)\t|\(.views)\t|\(.date)\t|\(.url)" else "" end' <"$ytfzf_video_json_file" | { command_exists "column" && column -s "$tab_space" -t; }
			;;
		*)
			command_exists "get_requested_info_$request" && "get_requested_info_$request"
			;;
		esac
	done
	end_of_set_args
	return 0
}

handle_info() {
	display_text_wrapper "$(get_requested_info "$ytfzf_selected_urls")"

	[ "$info_wait" -eq 1 ] && info_wait_prompt_wrapper

	case "$info_wait_action" in
        # simulates old behavior of when alt-l or alt-i is pressed and -l is enabled
        q) [ "$is_loop" -eq 1 ] && return 3 || return 2 ;;
        Q) return 2 ;;
        [MmCc]) return 3 ;;
        '') return 0 ;;
        *) if command_exists "custom_info_wait_action_$info_wait_action"; then custom_info_wait_action_"$info_wait_action"; else print_error "info_wait_action is set to $info_wait_action but custom_info_wait_action_$info_wait_action does not exist${new_line}"; fi ;;
	esac
	return 0

}

submenu_handler() {
	# eat stdin and close it
	cat >/dev/null
	old_interface="$interface"
	old_thumbnail_viewer="$thumbnail_viewer"
	[ "$keep_vars" -eq 0 ] && set_vars 0
	search="$(get_key_value "$_submenu_actions" "search")"
	__scrape="$(get_key_value "$_submenu_actions" "type")"
	submenu_opts="$old_submenu_scraping_opts $old_submenu_opts -c${__scrape}"
	# this needs to be here as well as close_url_handler because it will not happen inside this function if it's not here
	url_handler="$old_url_handler"
	thumbnail_viewer="$old_thumbnail_viewer"
	interface="$old_interface"
	unset old_interface
	(
		# shellcheck disable=2030
		export __is_submenu=1

		# shellcheck disable=2030
		cache_dir="${session_cache_dir}"

		if [ -f "$YTFZF_CONFIG_DIR/submenu-conf.sh" ]; then
			# shellcheck disable=1091
			. "$YTFZF_CONFIG_DIR/submenu-conf.sh"
		elif [ -f "$YTFZF_CONFIG_FILE" ]; then
			# shellcheck disable=1091
			# shellcheck disable=1090
			. "$YTFZF_CONFIG_FILE"
		fi

		prepare_for_set_args
		# shellcheck disable=2086
		set -- $submenu_opts "$search"
		end_of_set_args

		on_opt_parse_s() {
			print_warning "-s is not supported in submenus${new_line}"
		}

		_getopts "$@"

		source_scrapers

		search_again=0

		shift $((OPTIND - 1))

		init_and_make_search "$*" "fn-args"
		if [ "$enable_back_button" -eq 1 ]; then
			data="$(cat "$ytfzf_video_json_file")"
			echo '[{"ID": "BACK-BUTTON", "title": "[BACK]", "url": "back", "action": "back"}]' "$data" >"$ytfzf_video_json_file"
		fi

		something_was_scraped || exit 4

		main
	)
	submenu_opts="$old_submenu_opts"
	submenu_scraping_opts="$old_submenu_scraping_opts"
}

close_url_handler_submenu_handler() {
	url_handler="$old_url_handler"
	submenu_opts="$old_submenu_opts"
	submenu_scraping_opts="$old_submenu_scraping_opts"
}

close_url_handler() {
	fn_name="$(printf "%s" "$1" | tr '-' '_')"
	command_exists "close_url_handler_$fn_name" && close_url_handler_"$fn_name"
	print_debug "[URL HANDLER]: Closing url handler: ${c_blue}${1}${c_reset} with function: ${c_bold}close_url_handler_${fn_name}${c_reset}${new_line}"
	do_an_event_function "after_close_url_handler" "$1"
}

open_url_handler() {
	# isaudio, isdownload, ytdl_pref
	urls="$(tr '\n' ' ' <"$1")"

	prepare_for_set_args ' '
	# shellcheck disable=SC2086
	set -- $urls
	[ -z "$*" ] && print_info "No urls selected${new_line}" && return 0
	end_of_set_args

	do_an_event_function "on_open_url_handler" "$@"

	print_debug "[URL HANDLER]: Opening links: ${c_bold}${urls}${c_reset} with ${c_blue}${url_handler}${c_reset}${new_line}"

	# if we provide video_pref etc as arguments, we wouldn't be able to add more as it would break every url handler function
	# shellcheck disable=2031
	printf "%s\t" "$ytdl_pref" "$is_audio_only" "$is_detach" "$video_pref" "$audio_pref" "$url_handler_opts" | session_temp_dir="${session_temp_dir}" session_cache_dir="${session_cache_dir}" "$url_handler" "$@"
}
#}}}

# Format selection {{{
get_video_format_simple() {
	# select format if flag given
	formats=$(${ytdl_path} -F "$1" | grep -v "storyboard")
	# shellcheck disable=2059
	quality="$(printf "$formats" | grep -v "audio only" | sed -n '/^[[:digit:]]/s/.*[[:digit:]]\+x\([[:digit:]]\+\).*/\1p/p; 1i\Audio' | sort -n | uniq | quick_menu_wrapper "Video Quality" | sed "s/p//g")"
	if [ "$quality" = "Audio" ]; then
		is_audio_only=1
	elif expr "$formats" ":" ".*audio only" >/dev/null 2>&1; then
		video_format_no=$(printf "%s" "$formats" | grep -F "x$quality" | sed -n 1p)
		video_format_no="${video_format_no%% *}"
		ytdl_pref="${video_format_no}+bestaudio/bestaudio"
	else
		ytdl_pref="best[height=$quality]/best[height<=?$quality]/bestaudio"
	fi
	unset max_quality quality
}

get_video_format() {
    case "${ytdl_path##*/}" in
        (youtube-dl) _format_options=$("${ytdl_path}" -F "$1" | sed 1,3d) ;;
        (*) _format_options=$("${ytdl_path}" -q -F "$1" --format-sort "$format_selection_sort" | sed 1,3d) ;;
    esac
    _audio_choices="$(echo "$_format_options" | grep "audio only")"
	[ "$_audio_choices" ] && audio_pref="$(echo "$_audio_choices" | quick_menu_wrapper "Audio format: " | awk '{print $1}')"
	if [ "$is_audio_only" -eq 0 ]; then
        video_pref=$(echo "$_format_options" | sed 's/\\033\[[[:digit:]]*m//g' | grep -v 'audio only' | quick_menu_wrapper "Video Format: " | awk '{print $1}')
	fi
	ytdl_pref="${video_pref}+${audio_pref}/${video_pref}/${audio_pref}"
}

open_format_selection_if_requested() {
	[ "$show_formats" -eq 0 ] && return

	prepare_for_set_args
	#read from $ytfzf_selected_urls
	set -- $(tr '\n' ' ' <"$1")
	end_of_set_args

	print_debug "[INTERFACE]: [FORMAT SELECTION]: open format screen: ${c_blue}${format_selection_screen}${c_reset}${new_line}"
	case "$format_selection_screen" in
	normal)
		get_video_format "$1"
		;;
	*)
		get_video_format_$format_selection_screen "$@"
		;;
	esac
}

#}}}

# Internal Actions {{{
#
# Internal actions are usually called from fzf with the -W option.
# The point of these actions is to do something that can only be done given a specific ytfzf process instance. Such as displaying thumbnails

internal_action_help() {
	printf "%s\n" "Usage: ytfzf -W [help|preview_img]<EOT>[args...]
An action followed by \\003 (ascii: EOT) followed by args which are seperated by \\003.
Actions:
help:
    Prints usage on -W
preview_img <ytfzf-line-format>:
    ytfzf-line-format:
        path to file where items seperated by \t| where the last item is the url of the item
    The following variables must be set
        session_temp_dir set to the ytfzf process instance's temp dir
        session_cache_dir set to the ytfzf process instance's cache dir"
}

internal_action_next_page() {
	shift

	read -r line <"$*"
	url="${line##*"|"}"

	video_json_file="$ytfzf_video_json_file"

	hovered_scraper="$(jq -r '.[]|select(.url=="'"$url"'").scraper' <"$ytfzf_video_json_file")"

	if command_exists "scrape_next_page_$hovered_scraper"; then
		_search="$(cat "${session_cache_dir}/searches.list")"

		pages_start="$(cat "${session_temp_dir}/${hovered_scraper}-current-page")"
		pages_start="${pages_start#[\"\']}"
		pages_start="${pages_start%[\"\']}"

		scrape_next_page_"$hovered_scraper"
	fi

	_init_video_info_text "$TTY_COLS"

	create_sorted_video_data |
		video_info_text |
		_post_video_info_text
}

internal_action_preview_img() {
	shift

	thumb_dir="${session_cache_dir}/thumbnails"

	video_json_file="$ytfzf_video_json_file"

	line_file="$*"
	read -r line <"$line_file"
	line="${line#\'}" line="${line%\'}"
	source_scrapers
	preview_img "$thumbnail_viewer" "$line" "$ytfzf_video_json_file"
}
# }}}

# Options {{{
parse_opt() {
	opt=$1
	optarg=$2
	# for some reason optarg may equal opt intentionally,
	# this checks the unmodified optarg, which will only be equal if there is no = sign
	[ "$opt" = "$OPTARG" ] && optarg=""
	print_debug "[OPTIONS]: Parsing opt: $opt=$optarg${new_line}"
	# shellcheck disable=SC2031
	command_exists "on_opt_parse" && { on_opt_parse "$opt" "$optarg" "$OPT" "$OPTARG" || return 0; }
	fn_name="on_opt_parse_$(printf "%s" "$opt" | tr '-' '_')"
	# shellcheck disable=SC2031
	command_exists "$fn_name" && { $fn_name "$optarg" "$OPT" "$OPTARG" || return 0; }
	case $opt in
	h | help)
		usage
		exit 0
		;;
	D | external-menu) [ -z "$optarg" ] || [ "$optarg" -eq 1 ] && interface='ext' ;;
	m | audio-only) is_audio_only=${optarg:-1} ;;
	d | download) url_handler=downloader ;;
	f | formats) show_formats=${optarg:-1} ;;
	S | select) interface="scripting" && is_specific_select="1" && scripting_video_count="$optarg";;
	a | auto-select) [ -z "$optarg" ] || [ "$optarg" -eq 1 ] && is_auto_select=${optarg:-1};;
	A | select-all) [ -z "$optarg" ] || [ "$optarg" -eq 1 ] && is_auto_select=${optarg:-1} && scripting_video_count='$';;
	r | random-select) [ -z "$optarg" ] || [ "$optarg" -eq 1 ] && is_random_select=${optarg:-1};;
	n | link-count) scripting_video_count=$optarg ;;
	l | loop) is_loop=${optarg:-1} ;;
	s | search-again) search_again=${optarg:-1} ;;
	t | show-thumbnails) show_thumbnails=${optarg:-1} ;;
	version)
		printf 'ytfzf: %s \n' "$YTFZF_VERSION"
		exit 0
		;;
	version-all)
		printf -- '---\n%s: %s\n' "ytfzf" "$YTFZF_VERSION" "jq" "$(jq --version)" "curl" "$(curl --version)"
		exit 0
		;;
	L) info_to_print="$info_to_print,L" ;;
	pages) pages_to_scrape="$optarg" ;;
	pages-start) pages_start="$optarg" ;;
	thumbnail-log) thumbnail_debug_log="${optarg:-/dev/stderr}" ;;
	odysee-video-count) odysee_video_search_count="$optarg" ;;
	ii | inv-instance) invidious_instance="$optarg" ;;
	rii | refresh-inv-instances) refresh_inv_instances ;;
	i | interface) load_interface "$optarg" || die 2 "$optarg is not an interface${new_line}" ;;
	c | scrape) scrape=$optarg ;;
	scrape+) scrape="$scrape,$optarg" ;;
	scrape-) scrape="$(printf '%s' "$scrape" | sed 's/'"$optarg"'//; s/,,/,/g')" ;;
	I) info_to_print=$optarg ;;
	notify-playing) notify_playing="${optarg:-1}" ;;
	# long-opt exclusives
	sort)
		: "${optarg:=1}"
		if [ "$optarg" != 1 ] && [ "$optarg" != 0 ]; then
			is_sort="1"
			load_sort_name "$optarg" || die 2 "$optarg is not a sort-name${new_line}"
		else
			is_sort=${optarg}
		fi
		;;
	sort-name)
		# shellcheck disable=SC2015
		load_sort_name "$optarg" && is_sort=1 || die 2 "$optarg is not a sort-name${new_line}"
		;;
	video-pref) video_pref=$optarg ;;
	ytdl-pref) ytdl_pref=$optarg ;;
	audio-pref) audio_pref=$optarg ;;
	detach) is_detach=${optarg:-1} ;;
	ytdl-opts) ytdl_opts="$optarg" ;;
	ytdl-path) ytdl_path="$optarg" ;;
	preview-side)
		fzf_preview_side="${optarg}"
		[ -z "$fzf_preview_side" ] && die 2 "no preview side given${new_line}"
		;;
	T | thumb-viewer) load_thumbnail_viewer "$optarg" || [ -f "$thumbnail_viewer" ] || die 2 "$optarg is not a thumb-viewer${new_line}" ;;
	force-youtube) yt_video_link_domain="https://www.youtube.com" ;;
    force-invidious) yt_video_link_domain="" ;;
	info-print-exit | info-exit) [ "${optarg:-1}" -eq 1 ] && info_wait_action=q ;;
	info-action) info_wait_action="$optarg" ;;
	info-wait) info_wait="${optarg:-1}" ;;
	sort-by) search_sort_by="$optarg" ;;
	upload-date) search_upload_date="$optarg" ;;
	video-duration) search_video_duration=$optarg ;;
	type) search_result_type=$optarg ;;
	features) search_result_features=$optarg ;;
	region) search_region=$optarg ;;
	channel-link)
		invidious_instance=$(get_random_invidious_instance)
		_get_real_channel_link "$optarg"
		exit 0
		;;
	available-inv-instances)
		get_invidious_instances
		exit 0
		;;
	disable-submenus) enable_submenus="${optarg:-0}" ;;
	disable-actions) enable_actions="$((${optarg:-1} ^ 1))" ;;
	thumbnail-quality) thumbnail_quality="$optarg" ;;
	u | url-handler) load_url_handler "$optarg" ;;
	keep-cache) keep_cache="${optarg:-1}" ;;
	submenu-opts | submenu-scraping-opts) submenu_opts="${optarg}" ;;
	keep-vars) keep_vars="${optarg:-1}" ;;
	nsfw) nsfw="${optarg:-true}" ;;
	max-threads | single-threaded) max_thread_count=${optarg:-1} ;;
	# flip the bit
	disable-back) enable_back_button=${optarg:-0} ;;
	skip-thumb-download) skip_thumb_download=${optarg:-1} ;;
	multi-search) multi_search=${optarg:-1} ;;
	search-source) search_source="${optarg:-args}" ;;
	format-selection) format_selection_screen=${optarg:-normal} ;;
	format-sort) format_selection_sort="$optarg" ;;
	e | ext) load_extension "$optarg" ;;
	url-handler-opts) url_handler_opts="$optarg" ;;
	list-addons)
		for path in "$YTFZF_THUMBNAIL_VIEWERS_DIR" "$YTFZF_SORT_NAMES_DIR" \
			"$YTFZF_CUSTOM_INTERFACES_DIR" "$YTFZF_URL_HANDLERS_DIR" "$YTFZF_EXTENSIONS_DIR"; do
			! [ -d "$path" ] && continue
			printf "${c_bold}%s:${c_reset}\n" "user addon, ${path##*/}"
			ls "$path"
		done

		echo ----------------

		[ ! -d "$YTFZF_SYSTEM_ADDON_DIR" ] && exit

		set +f
		for path in "$YTFZF_SYSTEM_ADDON_DIR"/*; do
			printf "${c_bold}%s:${c_reset}\n" "system addon, ${path##*/}"
			ls "$path"
		done
		exit
		;;
	async-thumbnails) async_thumbnails="${optarg:-1}" ;;
	fancy-subs)
		fancy_subs=${optarg:-1}
		[ "$fancy_subs" -eq 1 ] && is_sort=0
		;;
	W)
		prepare_for_set_args "$EOT"
		set -- $optarg
		end_of_set_args
		action="$1"
		var_fifo="$session_cache_dir/var-fifo"
		command_exists "internal_action_$1" && internal_action_"$1" "$@"
		exit 0
		;;
	*)
		# shellcheck disable=SC2031
		[ "$OPT" = "$long_opt_char" ] && print_info "$0: illegal long option -- $opt${new_line}"
		;;
	esac
}

_getopts() {
	case "$long_opt_char" in
	[a-uw-zA-UW-Z0-9]) die 2 "long_opt_char must be v or non alphanumeric${new_line}" ;;
	#? = 1 char, * = 1+ chars; ?* = 2+ chars
	??*) die 2 "long_opt_char must be 1 char${new_line}" ;;
	esac

	OPTIND=0

	while getopts "${optstring:=ac:de:fhi:lmn:qrstu:xADHI:LS:T:W:${long_opt_char}:}" OPT; do
		case $OPT in
		"$long_opt_char")
			parse_opt "${OPTARG%%=*}" "${OPTARG#*=}"
			;;
		*)
			parse_opt "${OPT}" "${OPTARG}"
			;;
		esac
	done
}

_getopts "$@"
# shellcheck disable=SC2031
shift $((OPTIND - 1))
#}}}

do_an_event_function "on_post_set_vars"

# Get search{{{
#$initial_search should be used before make_search is called
#$_search should be used in make_search or after it's called and outisde of any scrapers themselves
#$search should be used in a scraper: eg scrape_json_file
unset IFS
: "${initial_search:=$*}"
#}}}

# files {{{
init_files() {
	#$1 will be a search
	SEARCH_PREFIX=$(printf "%s" "$1" | tr '/' '_' | tr -d "\"'")
	# shellcheck disable=SC2031
	if [ "$__is_submenu" -eq 1 ]; then
		SEARCH_PREFIX=$(jq -r --arg url "$1" '.[]|select(.url==$url).title' <"${cache_dir}/videos_json")
	fi

	# if no search is provided, use a fallback value of SCRAPE-$scrape
	SEARCH_PREFIX="${SEARCH_PREFIX:-SCRAPE-$scrape}"
	[ "${#SEARCH_PREFIX}" -gt 200 ] && SEARCH_PREFIX="SCRAPE-$scrape"

    #if we are in a submenu, cache_dir will be the previous session_cache_dir

    [ "$__is_submenu" -eq 1 ] && _session_cache_dir_prefix="${cache_dir}" || _session_cache_dir_prefix="${YTFZF_TEMP_DIR}"
    session_cache_dir="${_session_cache_dir_prefix}/${SEARCH_PREFIX}-${YTFZF_PID}"

	session_temp_dir="${session_cache_dir}/tmp"

	thumb_dir="${session_cache_dir}/thumbnails"

	ytfzf_selected_urls=$session_cache_dir/ids
	ytfzf_video_json_file=$session_cache_dir/videos_json

	mkdir -p "$session_temp_dir" "$thumb_dir"

	keypress_file="${session_temp_dir}/menu_keypress"

	: >"$ytfzf_video_json_file" 2>"$ytfzf_selected_urls" 3>"$keypress_file"

	[ "$1" ] && printf "%s\n" "$1" >"${session_cache_dir}/searches.list"

    awk 'BEGIN{print srand(srand())}' > "${session_cache_dir}/created-at"

    unset _session_cache_dir_prefix
}

# }}}

# actions {{{

############################
#         ACTIONS          #
############################

# Actions happen after a video is selected, and after the keypresses are handled

# Actions are formatted in the following way
# action-name data...
# for the scrape action, data must be formatted in the following way,
# For custom actions, data can be formatted in any way
# scrape search=search-in-one-word type=scraper

# actions are attached to videos/items in the menu
handle_actions() {
	unset _submenu_actions IFS
	[ "$enable_actions" -eq 0 ] && return 0
	actions=$(jq -r --arg urls "$(cat "$1")" '.[] | [.url, .action] as $data | if ( ($urls | split("\n" )) | index($data[0]) and $data[1] != null ) == true then $data[1] else "" end' <"$ytfzf_video_json_file" | sed '/^[[:space:]]*$/d')
	while read -r action; do
		print_debug "[ACTION]: handling action: $action${new_line}"

		# this wil only be empty after all urls with actions have happened
		# shellcheck disable=SC2031
		# shellcheck disable=SC2086
		case "$action" in
		back*) [ $__is_submenu -eq 1 ] && exit ;;
		scrape*)
			[ $enable_submenus -eq 0 ] && continue
			old_url_handler="$url_handler"
			old_submenu_opts="$submenu_opts"
			old_submenu_scraping_opts="$submenu_scraping_opts"
			url_handler=submenu_handler
			_submenu_actions="${_submenu_actions}${new_line}${action}"
			;;
		do-nothing*) return 1 ;;
		*)
			fn_name="handle_custom_action_$(printf "%s" "${action%% *}" | tr '-' '_')"
			if command_exists "$fn_name"; then
				$fn_name "${action#* }"
			elif command_exists "handle_custom_action"; then
				handle_custom_action "$action"
			fi || return $?
			;;
		esac
		break # TODO: allow multiple actions or at least let the action decide whether or not it can handle multiple actions
	done <<-EOF
		    $actions
	EOF
}

#}}}

# scraping wrappers {{{

set_scrape_count() {
	prepare_for_set_args ","
	# shellcheck disable=SC2086
	set -- $scrape
	end_of_set_args
	__total_scrape_count="$#"
}

handle_scrape_error() {
	_scr="$2"
	case "$1" in
	1) print_info "$_scr failed to load website${new_line}" ;;
	6) print_error "Website ($_scr) unresponsive (do you have internet?)${new_line}" ;;
	9) print_info "$_scr does not have a configuration file${new_line}" ;;
	22)
		case "$_scr" in
		youtube | Y | youtube-trending | T)
			print_error "There was an error scraping $_scr ($invidious_instance)${new_line}Try changing invidious instances${new_line}"
			;;
		*) print_error "There was an error scraping $_scr${new_line}" ;;
		esac
		;;
	#:help search operator
    100) print_info "---------${new_line}" && return 100 ;;
	126) print_info "$_scr does not have execute permissions${new_line}" ;;
	127) die 2 "invalid scraper: $_scr${new_line}" ;;
	*) print_error "An error occured while scraping: $_scr (scraper returned error: $1)${new_line}" ;;
	esac
}

handle_scraping() {
	_search="$1"
	prepare_for_set_args ","
	# if there is only 1 scraper used, multi search is on, then multiple searches will be performed seperated by ,
	__scrape_count=0
	__ret=0
	for curr_scrape in $scrape; do
		__scrape_count=$((__scrape_count + 1))
		do_an_event_function "ext_on_search" "$_search" "$curr_scrape"
		command_exists "on_search_$_search" && "on_search_$_search" "$curr_scrape"
		"scrape_$(printf '%s' "$curr_scrape" | sed 's/-/_/g')" "$_search" "$ytfzf_video_json_file"
		__ret=$?
		if [ $__ret != 0 ]; then
			handle_scrape_error $__ret "$curr_scrape"
		fi
	done
	[ $? -eq 100 ] && exit 0
	end_of_set_args
}

# check if nothing was scraped{{{
something_was_scraped() {
	#this MUST be `! grep -q -v -e '\[\]` because it's possible that [] exists in the file IN ADDITION to a list of actual results, we want to see if those actual results exists.
	if ! [ -s "${ytfzf_video_json_file}" ] || ! grep -q -v -e '\[\]' "$ytfzf_video_json_file"; then
		print_error "Nothing was scraped${new_line}"
		return 1
	fi
	return 0
}
#}}}

is_asking_for_search_necessary() {
	prepare_for_set_args ","
	for _scr in $scrape; do
		[ "${scrape_search_exclude#*" $_scr "}" = "${scrape_search_exclude}" ] && return 0
	done
	end_of_set_args
	return 1
}

init_search() {
	_search="$1"
	_search_source="$2"

	print_debug "[SEARCH]: initializing search with search: $_search, and sources: $_search_source${new_line}"

	# only ask for search if scrape isn't something like S or T
	is_asking_for_search_necessary && { get_search_from_source "$_search_source" "$_search" || die 5 "No search query${new_line}"; }
	init_files "$_search"
	set_scrape_count

	# shellcheck disable=SC2031

	do_an_event_function "on_init_search" "$_search"
}

init_and_make_search() {
	_search=$1
	_search_source=$2
	init_search "$_search" "$_search_source"
	make_search "$_search"
}

make_search() {
	_search="$1"
	handle_scraping "$_search"
	do_an_event_function post_scrape
}
#}}}

# Main {{{

init_and_make_search "$initial_search" "$search_source"
until something_was_scraped; do
	case "$search_again" in
	0) exit 4 ;;
	1) init_and_make_search "" "$search_source" ;;
	esac
done

main() {
	while :; do
		# calls the interface only if we shouldn't auto select
		auto_select "$ytfzf_video_json_file" "$ytfzf_selected_urls" || run_interface

		handle_keypress "$keypress_file" || case "$?" in
		2) break ;; 3) continue ;; esac

		handle_actions "$ytfzf_selected_urls" || case "$?" in
		2) break ;; 3) continue ;; esac

		# nothing below needs to happen if  this is empty (causes bugs when this is not here)
		[ ! -s "$ytfzf_selected_urls" ] && break

		# shellcheck disable=SC2015
		if [ "$info_to_print" ]; then
			handle_info
			case "$?" in
			2) break ;; 3) continue ;; esac
		fi

		open_format_selection_if_requested "$ytfzf_selected_urls"

		open_url_handler "$ytfzf_selected_urls"
		close_url_handler "$url_handler"

		[ "$is_loop" -eq 0 ] && break
	done
}

main
# doing this after the loop allows for -l and -s to coexist
while [ "$search_again" -eq 1 ]; do
	clean_up
	initial_search= init_and_make_search "" "$search_source"
	main
done
#}}}

# vim: foldmethod=marker:shiftwidth=4:tabstop=4
