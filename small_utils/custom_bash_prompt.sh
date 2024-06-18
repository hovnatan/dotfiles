prompt_command() {
  # if PWD has not changed, just return
  [[ $PWD == $_cust_hist_opwd ]] && return

  function iscustom {
    # returns 'true' if the passed argument is a custom-history directory
    case "$1" in
      # ( */home/hovnatan/work/s | */home/hovnatan/work/db ) return 0;;
      ( *"$HOME/work/"* ) return 0;;
      ( * ) return 1;;
    esac
  }

  # PWD changed, but it's not to or from a custom-history directory,
  # so update opwd and return
  if ! iscustom "$PWD" && ! iscustom "$_cust_hist_opwd"
  then
    _cust_hist_opwd=$PWD
    return
  fi

  # we've changed directories to and/or from a custom-history directory

  # save the new PWD
  _cust_hist_opwd=$PWD

  # save and then clear the old history
  history -a
  history -c

  # if we've changed into or out of a custom directory, set or reset HISTFILE appropriately
  if iscustom "$PWD"
  then
    HISTFILE=$PWD/.bash_history
  else
    HISTFILE=$_cust_hist_stock_histfile
  fi

  # pull back in the previous history
  history -r
}

PROMPT_COMMAND='history -a;prompt_command'
_cust_hist_stock_histfile=$HISTFILE
_cust_hist_opwd=""
