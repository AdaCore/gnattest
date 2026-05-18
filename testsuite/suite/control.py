from argparse import ArgumentParser


def add_shared_options_to(parser: ArgumentParser):
    """
    Shared command line options.

    Options allowed at the testsuite.py level which need to be passed down to
    individual test.py.
    """
    # RTS for tested programs. Defaulting to "" instead of None lets us
    # perform RE searches unconditionally to determine profile.
    parser.add_argument(
        "--RTS",
        dest="RTS",
        metavar="RTS",
        default="",
        help='--RTS option to pass to gprbuild, if any. Assume "full" profile'
        " by default.",
    )

    parser.add_argument(
        "--log-all",
        dest="log_all",
        action="store_true",
        help="Log the output of all commands to test_instance.log and "
        "test_instance.err",
    )
