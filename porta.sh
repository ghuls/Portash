#!/usr/bin/env bash

# ____            _              _
# |  _ \ ___  _ __| |_ __ _   ___| |__
# | |_) / _ \| '__| __/ _` | / __| '_ \
# |  __/ (_) | |  | || (_| |_\__ \ | | |
# |_|   \___/|_|   \__\__,_(_)___/_| |_|

echoerr() { echo "$@" 1>&2; }

show_usage() {
  echo "Usage: "$0" [dry-run]"
  echo ""
  exit 1
}

# Retrieve the content of a path
# $1: the input, JSON or YAML
# $2: string denoting the path, dots separate levels
get_path() {
  local input=$1
  local path=$2
  out=$(echo "$input" | yq r - -- "$2" 2> /dev/null)
  ret=$?
  if [ $ret -ne 0 ]; then
    echoerr "YAML/JSON parsing error in get_path(), please check input"
    exit 1
  else
    echo "$out"
  fi
}

# Add content
put_path() {
  local input=$1
  local path=$2
  local content=$3
  out=$(echo "$input" | yq w - "$2" "$3" 2> /dev/null)
  ret=$?
  if [ $ret -ne 0 ]; then
    echoerr "YAML/JSON parsing error in put_path(), please check input"
    exit 1
  else
    echo "$out"
  fi
}

# Convenience function to count the number of elements in an array
nr_arguments() {
  local input=$1
  local path=$2
  # Select arguments block
  arguments=$(echo "$input" | yq r - -- "$path" 2> /dev/null)
  ret=$?
  if [ $ret -ne 0 ]; then
    echoerr "YAML/JSON parsing error in nr_arguments(), please check input"
    exit 1
  fi
  # Number of arguments
  local N=$(echo "$arguments" | yq r - '[*]' | wc -l | xargs)
  echo -n "$N"
}

# Parse all arguments in an array
# Input:
#   - YAML/JSON blob
#   - path to the array
# Output: string with all arguments
# ------------------------------------------------
parse_arguments() {
  local input=$1
  local path=$2
  # Select arguments block
  N=$(nr_arguments "$input" "$path" 2> /dev/null)
  ret=$?
  if [ $ret -ne 0 ]; then
    echoerr "YAML/JSON parsing error in parse_arguments(), please check input"
    exit 1
  fi
  # Loop over members of argument array
  for ((i=0; i<$N; i++))
  do
    local this_path="$path"\[$i\]
    local this_argument=$(get_path "$input" "$this_path")
    echo -n $(get_path "$this_argument")
    echo -n " "
  done
}

# Parse 1 parameter hash [name -> value]
# Input: 1 element of the parameter array
# Output: string of the form --parameter value
# ------------------------------------------------
parse_parameter() {
  local input=$1
  parameter=$(echo "$input" | yq r - -- "name" 2> /dev/null)
  ret=$?
  if [ $ret -ne 0 ]; then
    echoerr "YAML/JSON parsing error in parse_parameter() name, please check input"
    exit 1
  else
    value=$(echo "$input" | yq r - -- "value" 2> /dev/null)
    ret=$?
    if [ $ret -ne 0 ]; then
      echoerr "YAML/JSON parsing error in parse_parameter() value, please check input"
      exit 1
    else
      echo -n "--$parameter $value"
    fi
  fi
}

# Convenience function to count the number of elements in an array
nr_parameters() {
  local input=$1
  local path=$2
  # Select parameters block
  parameters=$(echo "$input" | yq r - -- "$path" 2> /dev/null)
  ret=$?
  if [ $ret -ne 0 ]; then
    echoerr "YAML/JSON parsing error in nr_parameters(), please check input"
    exit 1
  else
    # Number of parameters
    local N=$(echo "$parameters" | yq r - '[*].name' | wc -l | xargs)
    echo -n "$N"
  fi
}

# Parse all parameters in an array
# Input:
#   - YAML/JSON blob
#   - path to the array
# Output: string with all parameters
# ------------------------------------------------
parse_parameters() {
  local input=$1
  local path=$2
  # Select parameters block
  N=$(nr_parameters "$input" "$path" 2> /dev/null)
  ret=$?
  if [ $ret -ne 0 ]; then
    echoerr "YAML/JSON parsing error in parse_parameters(), please check input"
    exit 1
  fi
  # Loop over members of parameter array
  for ((i=0; i<$N; i++))
  do
    local this_path="$path"\[$i\]
    local this_parameter=$(get_path "$input" "$this_path")
    # echo "$this_path"
    echo -n $(parse_parameter "$this_parameter")
    echo -n " "
  done
}

# End of generic part
# ============================================================================

# Actual RUN function...
runner() {
  local commandline="$@"
  if [ "$DRY" = true ]
  then
    PREFIX='echo Running command: '
  else
    PREFIX=''
  fi
  OUT=$($PREFIX$commandline 2> /tmp/err.log)
  echo "$OUT"
}

# Actual PARSER
parser() {
  local input=$1
  command=$(get_path "$input" "function.command")
  arguments=$(parse_arguments "$input" "function.arguments")
  echo "$command $arguments"
}

# main function
# Supports:
# - Dry run (using `dry-run` as first argument)
# - standard input or file
main() {

  # See if this is a dry-run or not
  if [ "$1" == "dry-run" ]; then
    DRY=true
    echo "Dry mode on, prefixing everything with 'echo'"
    shift
  fi

  # Read standard input or file as first argument
  [ $# -ge 0 -a -f "$1"  ] && input="$(cat $1)" && shift || input="$(cat)"

  # Run through parser
  commandline=$(parser "$input")
  # Run command
  output=$(runner "$commandline")

  # Append output and errors to config (may not be required)
  parsed=$(put_path "$input" "output.result" "$output")
  err=$(cat /tmp/err.log)
  parsed=$(put_path "$parsed" "output.error" "$err")
  echo "$parsed"
}

# Some machinery to make this script easily 'sourceable' for tests
script_name=$( basename ${0#-} ) #- needed if sourced no path
this_script=$( basename ${BASH_SOURCE} )

if [[ ${script_name} = ${this_script} ]] ; then
    # running main here, otherwise leave control
    main "$@"
fi

# END