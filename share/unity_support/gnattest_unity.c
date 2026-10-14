/****************************************************************************
 *                                                                          *
 *                                 GNATtest                                 *
 *                                                                          *
 *                     Copyright (C) 2026, AdaCore                          *
 *                                                                          *
 * GNATtest  is  free  software; you  can  redistribute  it  and/or  modify *
 * it  under  terms of the  GNU  General  Public  License  as  published by *
 * the Free Software Foundation;  either version 3, or (at your option) any *
 * later version. This software  is distributed in the hope that it will be *
 * useful but  WITHOUT  ANY  WARRANTY; without even the implied warranty of *
 * MERCHANTABILITY  or  FITNESS  FOR A PARTICULAR PURPOSE.                  *
 *                                                                          *
 ****************************************************************************/

/* For dup and fileno under a strict C standard.  */
#if (defined(__unix__) || defined(__APPLE__)) && !defined(_XOPEN_SOURCE)
#define _XOPEN_SOURCE 700
#endif

#include <stdio.h>
#include <string.h>

#include "gnattest_unity.h"

/* A hosted target lets the driver capture what a test prints and time each
   test.  Elsewhere the driver needs nothing but putchar.  */
#if defined(__unix__) || defined(__APPLE__) || defined(_WIN32)
#define GNATTEST_HOSTED 1
#include <stdlib.h>
#include <time.h>
#ifdef _WIN32
#include <io.h>
#define dup _dup
#define dup2 _dup2
#define fileno _fileno
#define close _close
#else
#include <unistd.h>
#endif
#endif

#ifndef GNATTEST_MESSAGE_SIZE
#define GNATTEST_MESSAGE_SIZE 4096
#endif

/******************
 * Output capture *
 ******************/

/* What Unity prints during a test: its failure, ignore and info lines.  */
static char unity_output[GNATTEST_MESSAGE_SIZE];
static size_t unity_output_length;
static int capturing;

/* Whether what the code under test printed may have reached stdout since the
   last result: without an operating system, or when the capture failed.  A
   result then starts on a new line, so that it is not glued to that output
   and readers still find it.  */
static int output_uncaptured;

void
gnattest_unity_output_char (int c)
{
  if (!capturing)
    putchar (c);
  else if (unity_output_length < sizeof (unity_output) - 1)
    unity_output[unity_output_length++] = (char) c;
}

static void
start_capture (void)
{
  unity_output_length = 0;
  capturing = 1;
}

static void
stop_capture (void)
{
  unity_output[unity_output_length] = '\0';
  capturing = 0;
}

/* End the captured Unity line if one is open.  Unity leaves its fatal
   failure lines unterminated until it concludes the test, so a message that
   a tear-down prints would otherwise be glued to that failure.  */
static void
close_unity_line (void)
{
  if (capturing && unity_output_length > 0
      && unity_output[unity_output_length - 1] != '\n')
    gnattest_unity_output_char ('\n');
}

/************
 * Messages *
 ************/

/* A message built for a result, without the C library, which a bareboard
   target may lack.  */
static char check_message[GNATTEST_MESSAGE_SIZE];
static size_t check_message_length;

static void
append (const char *s)
{
  while (*s != '\0' && check_message_length < sizeof (check_message) - 1)
    check_message[check_message_length++] = *s++;
  check_message[check_message_length] = '\0';
}

/*************
 * Selection *
 *************/

/* The character at i of the report name of t, "suite.name", which is never
   built: a name may be longer than any buffer.  */
static char
name_char (const gnattest_test *t, size_t suite_len, size_t i)
{
  if (i < suite_len)
    return t->suite->name[i];
  if (i == suite_len)
    return '.';
  return t->name[i - suite_len - 1];
}

/* Whether pattern matches the whole report name of t, '*' standing for any
   run of characters and '?' for any one character.  The same rule as the
   --filter switch of the Ada drivers, so one pattern selects the same
   names.  */
static int
name_matches (const gnattest_test *t, const char *pattern)
{
  size_t suite_len = strlen (t->suite->name);
  size_t length = suite_len + 1 + strlen (t->name);
  size_t i = 0, resume = 0;
  const char *star = NULL;

  while (i < length)
    {
      char c = name_char (t, suite_len, i);

      if (*pattern == '?' || (*pattern != '\0' && *pattern == c))
        {
          pattern++;
          i++;
        }
      else if (*pattern == '*')
        {
          star = pattern++;
          resume = i;
        }
      else if (star != NULL)
        {
          /* Let the last '*' swallow one more character.  */
          pattern = star + 1;
          i = ++resume;
        }
      else
        return 0;
    }

  while (*pattern == '*')
    pattern++;
  return *pattern == '\0';
}

static int
selected (const gnattest_test *t, const char *filter)
{
  return filter == NULL || filter[0] == '\0' || name_matches (t, filter);
}

/*************************
 * Process output, hosted *
 *************************/

#ifdef GNATTEST_HOSTED

/* What the test itself prints on stdout and stderr goes to a temporary file
   so that it cannot interleave with the results on stdout.  */
static FILE *test_output;
static int saved_stdout = -1, saved_stderr = -1;

static void
redirect_process_output (void)
{
  fflush (stdout);
  fflush (stderr);
  test_output = tmpfile ();
  if (test_output == NULL)
    {
      output_uncaptured = 1;
      return;
    }
  saved_stdout = dup (1);
  saved_stderr = dup (2);
  dup2 (fileno (test_output), 1);
  dup2 (fileno (test_output), 2);
}

/* Restore stdout and stderr, and return what the test printed, or NULL.
   Store its byte count in length.  The caller frees the result.  */
static char *
restore_process_output (size_t *length)
{
  char *text = NULL;
  long size;

  *length = 0;
  if (test_output == NULL)
    return NULL;

  fflush (stdout);
  fflush (stderr);
  dup2 (saved_stdout, 1);
  dup2 (saved_stderr, 2);
  close (saved_stdout);
  close (saved_stderr);

  size = ftell (test_output);
  if (size > 0)
    {
      text = (char *) malloc ((size_t) size + 1);
      if (text != NULL)
        {
          rewind (test_output);
          size = (long) fread (text, 1, (size_t) size, test_output);
          text[size] = '\0';
          *length = (size_t) size;
        }
    }
  fclose (test_output);
  test_output = NULL;
  return text;
}

static double
now (void)
{
  /* A wall clock can step back during a test.  */
#if defined(CLOCK_MONOTONIC) && !defined(_WIN32)
  struct timespec mono;
  if (clock_gettime (CLOCK_MONOTONIC, &mono) == 0)
    return (double) mono.tv_sec + (double) mono.tv_nsec / 1e9;
#endif
#ifdef TIME_UTC
  struct timespec ts;
  if (timespec_get (&ts, TIME_UTC) == TIME_UTC)
    return (double) ts.tv_sec + (double) ts.tv_nsec / 1e9;
#endif
  return (double) clock () / CLOCKS_PER_SEC;
}

#endif /* GNATTEST_HOSTED */

/***********
 * Results *
 ***********/

static void
put_string (const char *s)
{
  while (*s != '\0')
    putchar (*s++);
}

static void
put_number (unsigned long n)
{
  char digits[24];
  int i = 0;

  do
    {
      digits[i++] = (char) ('0' + n % 10);
      n /= 10;
    }
  while (n != 0);
  while (i > 0)
    putchar (digits[--i]);
}

/* Length of the valid UTF-8 sequence of non-ASCII characters that starts at
   s, or 0 if s does not start one.  The byte ranges are those of Table 3-7,
   "Well-Formed UTF-8 Byte Sequences", of the Unicode Standard.  The range of
   the second byte excludes overlong encodings, surrogates and code points
   beyond U+10FFFF.  */
static int
utf_8_length (const unsigned char *s, size_t remaining)
{
  int length, i;
  unsigned char low = 0x80, high = 0xBF;

  if (s[0] >= 0xC2 && s[0] <= 0xDF)
    length = 2;
  else if (s[0] >= 0xE0 && s[0] <= 0xEF)
    {
      length = 3;
      if (s[0] == 0xE0)
        low = 0xA0;
      else if (s[0] == 0xED)
        high = 0x9F;
    }
  else if (s[0] >= 0xF0 && s[0] <= 0xF4)
    {
      length = 4;
      if (s[0] == 0xF0)
        low = 0x90;
      else if (s[0] == 0xF4)
        high = 0x8F;
    }
  else
    return 0;

  if ((size_t) length > remaining)
    return 0;
  for (i = 1; i < length; i++)
    if (s[i] < (i == 1 ? low : 0x80) || s[i] > (i == 1 ? high : 0xBF))
      return 0;
  return length;
}

/* Put s as a JSON string.  Valid UTF-8 is kept; any other byte is taken as
   a Latin-1 character and escaped, so that every record is valid UTF-8, as
   in AUnit's JSON reporter.  */
static void
put_json_bytes (const char *s, size_t size)
{
  static const char hex[] = "0123456789abcdef";

  putchar ('"');
  for (; size != 0; s++, size--)
    {
      unsigned char c = (unsigned char) *s;
      int length;

      if (c >= 0x80)
        {
          length = utf_8_length ((const unsigned char *) s, size);
          if (length == 0)
            {
              put_string ("\\u00");
              putchar (hex[c >> 4]);
              putchar (hex[c & 0xf]);
            }
          else
            {
              size -= (size_t) length - 1;
              while (length-- > 1)
                putchar (*s++);
              putchar (*s);
            }
          continue;
        }

      switch (c)
        {
        case '"':
          put_string ("\\\"");
          break;
        case '\\':
          put_string ("\\\\");
          break;
        case '\n':
          put_string ("\\n");
          break;
        case '\r':
          put_string ("\\r");
          break;
        case '\t':
          put_string ("\\t");
          break;
        default:
          if (c < 0x20 || c == 0x7F)
            {
              put_string ("\\u00");
              putchar (hex[c >> 4]);
              putchar (hex[c & 0xf]);
            }
          else
            putchar (c);
        }
    }
  putchar ('"');
}

static void
put_json_string (const char *s)
{
  put_json_bytes (s, strlen (s));
}

static void
put_field (const char *key)
{
  putchar (',');
  put_json_string (key);
  putchar (':');
}

static void
put_location (const char *file, unsigned long line)
{
  put_string ("{\"file\":");
  put_json_string (file);
  put_string (",\"line\":");
  put_number (line);
  put_string (",\"col\":0}");
}

/* The outcome of one test, as reported in the result model.  */
typedef struct
{
  const char *status;
  const char *message;
  unsigned long failure_line;
  const char *output;
  size_t output_length;
  int timed;
  double elapsed;
} outcome;

static void
put_result (const gnattest_test *t, const outcome *o)
{
  if (output_uncaptured)
    {
      putchar ('\n');
      output_uncaptured = 0;
    }
  put_string ("{\"lang\":\"c\",\"path\":[");
  put_json_string (t->suite->name);
  putchar (',');
  put_json_string (t->name);
  putchar (']');
  put_field ("status");
  put_json_string (o->status);
  if (o->message != NULL && o->message[0] != '\0')
    {
      put_field ("message");
      put_json_string (o->message);
    }
  if (o->failure_line != 0)
    {
      put_field ("failure_at");
      put_location (t->file, o->failure_line);
    }
  if (o->timed)
    {
      unsigned long us =
        o->elapsed > 0.0 ? (unsigned long) (o->elapsed * 1e6) : 0;
      unsigned long scale;
      put_field ("elapsed");
      put_number (us / 1000000);
      putchar ('.');
      for (scale = 100000; scale > 0; scale /= 10)
        putchar ((char) ('0' + (us / scale) % 10));
    }
  if (o->output_length != 0)
    {
      put_field ("stdout");
      put_json_bytes (o->output, o->output_length);
    }
  put_string ("}\n");
  fflush (stdout);
}

/* Match a prefix after Unity escapes control bytes.  Non-ASCII bytes are
   passed through by unity_config.h and validated by the JSON writer.  */
static int
match_printed (const char **p, const char *end, const char *s)
{
  static const char hex[] = "0123456789ABCDEF";
  const char *q = *p;

  for (; *s != '\0'; s++)
    {
      unsigned char c = (unsigned char) *s;
      char escape[4];
      size_t length = 0, i;

      if (UNITY_IS_PRINTABLE_CHAR (c))
        escape[length++] = (char) c;
      else
        {
          escape[length++] = '\\';
          if (c == '\r')
            escape[length++] = 'r';
          else if (c == '\n')
            escape[length++] = 'n';
          else
            {
              escape[length++] = 'x';
              escape[length++] = hex[c >> 4];
              escape[length++] = hex[c & 0xf];
            }
        }
      if ((size_t) (end - q) < length)
        return 0;
      for (i = 0; i < length; i++)
        if (q[i] != escape[i])
          return 0;
      q += length;
    }
  *p = q;
  return 1;
}

/* Keep Unity's diagnostic escapes as text.  Decoding them would also
   change literal escape sequences written by the test.  */
static void
append_message (char *buf, size_t *length, size_t size, const char *msg,
                const char *end)
{
  while (msg < end && *length < size - 1)
    buf[(*length)++] = *msg++;
}

/* Unity has no API for a failure: it only prints it, as a line.  Copy into
   buf the messages of the captured Unity lines of t of the given kind
   ("FAIL", "IGNORE" or "INFO"), one per line.  Each such line reads
   "<file>:<line>:<test>:<KIND>", then ":" or "." and the message.  A line
   without that prefix continues the message before it, as when the message
   itself has line breaks.  Return the line of the first one, or 0 if there is
   none.  */
static unsigned long
extract_messages (const gnattest_test *t, const char *kind, char *buf,
                  size_t size)
{
  size_t name_len = strlen (t->name);
  size_t kind_len = strlen (kind);
  size_t length = 0;
  unsigned long first_line = 0;
  const char *read = unity_output;
  int in_message = 0;

  while (*read != '\0')
    {
      const char *eol = strchr (read, '\n');
      const char *end = eol != NULL ? eol : read + strlen (read);
      const char *p = read;
      unsigned long line = 0;

      if (match_printed (&p, end, t->file) && p < end && *p == ':')
        {
          in_message = 0;
          p++;
          while (*p >= '0' && *p <= '9')
            line = line * 10 + (unsigned long) (*p++ - '0');
          if (*p == ':' && strncmp (p + 1, t->name, name_len) == 0
              && p[1 + name_len] == ':'
              && strncmp (p + 2 + name_len, kind, kind_len) == 0)
            {
              const char *msg = p + 2 + name_len + kind_len;
              while (msg < end && (*msg == ':' || *msg == '.' || *msg == ' '))
                msg++;
              if (first_line == 0)
                first_line = line;
              else if (length < size - 1)
                buf[length++] = '\n';
              append_message (buf, &length, size, msg, end);
              in_message = 1;
            }
        }
      else if (in_message && read < end)
        {
          if (length < size - 1)
            buf[length++] = '\n';
          append_message (buf, &length, size, read, end);
        }
      read = eol != NULL ? eol + 1 : end;
    }
  buf[length] = '\0';
  return first_line;
}

/***********
 * Running *
 ***********/

static int failures;

/* The message of the current test, and the output it printed through
   Unity (TEST_MESSAGE, TEST_PRINTF).  */
static char message[GNATTEST_MESSAGE_SIZE];
static char unity_info[GNATTEST_MESSAGE_SIZE];

/* Output reported for a test: what it printed through Unity, then what it
   printed itself.  The result is to be freed by the caller.  */
static char *
combine_output (const char *info, char *printed, size_t *length)
{
#ifdef GNATTEST_HOSTED
  size_t info_len = strlen (info);
  size_t printed_len;
  char *all;

  if (info_len == 0)
    return printed;
  printed_len = *length;
  all = (char *) malloc (info_len + 1 + printed_len + 1);
  if (all == NULL)
    return printed;
  memcpy (all, info, info_len);
  all[info_len] = '\n';
  memcpy (all + info_len + 1, printed != NULL ? printed : "",
          printed_len + 1);
  free (printed);
  *length = info_len + 1 + printed_len;
  return all;
#else
  (void) printed;
  *length = strlen (info);
  return (char *) info;
#endif
}

/* Details can point into a previous test or fixture's stack frame.  */
static void
clear_details (void)
{
#ifndef UNITY_EXCLUDE_DETAILS
#ifdef UNITY_DETAIL_STACK_SIZE
  Unity.CurrentDetailStackSize = 0;
#else
  UNITY_CLR_DETAILS ();
#endif
#endif
}

static void
run_test (const gnattest_test *t)
{
  outcome o;
  char *output = NULL;
#ifdef GNATTEST_HOSTED
  double start = now ();
#endif

  memset (&o, 0, sizeof (o));
  /* Unity's own runner sets this state for each test.  The driver replaces
     that runner.  */
  Unity.CurrentTestName = t->name;
  Unity.CurrentTestLineNumber = (UNITY_LINE_TYPE) t->line;
  Unity.TestFile = t->file;
  Unity.NumberOfTests++;
  Unity.CurrentTestFailed = 0;
  Unity.CurrentTestIgnored = 0;
  clear_details ();

  start_capture ();
#ifdef GNATTEST_HOSTED
  redirect_process_output ();
#else
  output_uncaptured = 1;
#endif
  /* A failed assertion longjmps back to TEST_PROTECT, which ends the test.
     A test that crashes ends the run, as the process may be corrupted.  */
  if (TEST_PROTECT ())
    {
      if (t->suite->set_up != NULL)
        t->suite->set_up ();
      t->run ();
    }
  close_unity_line ();
  if (t->suite->tear_down != NULL && TEST_PROTECT ())
    t->suite->tear_down ();
#ifdef GNATTEST_HOSTED
  output = restore_process_output (&o.output_length);
  o.timed = 1;
  o.elapsed = now () - start;
#endif
  stop_capture ();

  /* Unity keeps no message: only these flags and the lines it printed.  */
  if (Unity.CurrentTestFailed)
    {
      o.status = "failed";
      o.failure_line = extract_messages (t, "FAIL", message, sizeof (message));
      o.message = message;
    }
  else if (Unity.CurrentTestIgnored)
    {
      o.status = "skipped";
      (void) extract_messages (t, "IGNORE", message, sizeof (message));
      o.message = message;
    }
  else
    o.status = "passed";

  (void) extract_messages (t, "INFO", unity_info, sizeof (unity_info));
  output = combine_output (unity_info, output, &o.output_length);
  o.output = output;

  if (Unity.CurrentTestFailed)
    failures++;
  put_result (t, &o);

#ifdef GNATTEST_HOSTED
  free (output);
#endif
  /* While they are set, Unity skips every assertion.  */
  Unity.CurrentTestFailed = 0;
  Unity.CurrentTestIgnored = 0;
}

/* Build in check_message the message of a failed suite fixture, described as
   what, from what it printed through Unity on behalf of the first test of the
   suite, t.  Return the line of the failure, or 0.  */
static unsigned long
fixture_failure (const gnattest_test *t, const char *what)
{
  unsigned long line = extract_messages (t, "FAIL", message, sizeof (message));

  check_message_length = 0;
  append (what);
  append (" failed");
  if (message[0] != '\0')
    {
      append (": ");
      append (message);
    }
  return line;
}

/* Report every selected test of tests[first .. last - 1] as failed, because
   the set-up of their suite failed.  */
static void
fail_suite (const gnattest_test *tests, int first, int last,
            const char *filter)
{
  unsigned long line;
  int i;

  /* The fixture ran on behalf of the first test of the suite.  */
  line = fixture_failure (&tests[first], "Suite set-up");

  for (i = first; i < last; i++)
    if (selected (&tests[i], filter))
      {
        outcome o;
        memset (&o, 0, sizeof (o));
        o.status = "failed";
        o.message = check_message;
        o.failure_line = line;
        put_result (&tests[i], &o);
        failures++;
      }
}

/* Run a suite fixture, on behalf of the first test of the suite for the
   messages, with the output capture of a test.  What it prints is dropped: a
   fixture has no result to report it with.  Return whether it succeeded.  */
static int
run_suite_fixture (gnattest_procedure f, const gnattest_test *t)
{
  int ok;
#ifdef GNATTEST_HOSTED
  size_t output_length;
#endif

  if (f == NULL)
    return 1;
  Unity.CurrentTestName = t->name;
  Unity.TestFile = t->file;
  Unity.CurrentTestFailed = 0;
  clear_details ();
  start_capture ();
#ifdef GNATTEST_HOSTED
  redirect_process_output ();
#else
  output_uncaptured = 1;
#endif
  if (TEST_PROTECT ())
    f ();
#ifdef GNATTEST_HOSTED
  free (restore_process_output (&output_length));
#endif
  close_unity_line ();
  stop_capture ();
  ok = !Unity.CurrentTestFailed;
  Unity.CurrentTestFailed = 0;
  return ok;
}

/* Report a failed tear-down of the suite of tests[first] as a result of its
   own, named after the macro that declares it.  */
static void
fail_suite_tear_down (const gnattest_test *tests, int first)
{
  gnattest_test fixture = tests[first];
  outcome o;

  memset (&o, 0, sizeof (o));
  o.failure_line = fixture_failure (&tests[first], "Suite tear-down");
  o.status = "failed";
  o.message = check_message;
  fixture.name = "TEAR_DOWN_SUITE";
  put_result (&fixture, &o);
}

/* Run the selected tests of tests[0 .. test_count - 1], each run of adjacent
   tests of one suite between its suite fixtures.  A suite with no selected
   test does not run them.  */
static void
run_table (const gnattest_test *tests, int test_count, const char *filter)
{
  int first, last, i;

  for (first = 0; first < test_count; first = last)
    {
      const gnattest_suite *suite = tests[first].suite;
      int any = 0;

      for (last = first; last < test_count && tests[last].suite == suite;
           last++)
        any = any || selected (&tests[last], filter);
      if (!any)
        continue;

      if (!run_suite_fixture (suite->set_up_suite, &tests[first]))
        {
          fail_suite (tests, first, last, filter);
          continue;
        }
      for (i = first; i < last; i++)
        if (selected (&tests[i], filter))
          run_test (&tests[i]);
      if (!run_suite_fixture (suite->tear_down_suite, &tests[first]))
        {
          fail_suite_tear_down (tests, first);
          failures++;
        }
    }
}

int
gnattest_unity_run (int argc, char **argv,
                    const gnattest_test_table *const *tables, int table_count)
{
  const char *filter = NULL;
  int exit_status = 0;
  int i;

  for (i = 1; i < argc; i++)
    if (strncmp (argv[i], "--filter=", 9) == 0)
      filter = argv[i] + 9;
    else if (strcmp (argv[i], "--exit-status=on") == 0)
      exit_status = 1;

  UnityBegin ("");
  failures = 0;

  for (i = 0; i < table_count; i++)
    run_table (tables[i]->tests, tables[i]->count, filter);

  return exit_status && failures > 0 ? 1 : 0;
}
