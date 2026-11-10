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

/* Unity configuration for gnattest.  Read by Unity itself when
   UNITY_INCLUDE_CONFIG_H is defined, which gnattest_unity.h ensures.  */

#ifndef GNATTEST_UNITY_CONFIG_H
#define GNATTEST_UNITY_CONFIG_H

/* Unity prints a failure instead of storing it.  The driver captures that
   output per test to put the message in the test's result.  */
extern void gnattest_unity_output_char (int c);
#define UNITY_OUTPUT_CHAR(c) gnattest_unity_output_char (c)
#define UNITY_OUTPUT_CHAR_HEADER_DECLARATION gnattest_unity_output_char (int)

/* Preserve UTF-8 bytes.  The JSON writer handles invalid sequences.  */
#define UNITY_IS_PRINTABLE_CHAR(c) \
  ((unsigned char) (c) >= 32 && (unsigned char) (c) != 127)

/* Unity excludes double-precision assertions by default.  */
#define UNITY_INCLUDE_DOUBLE

/* Unity separates a message from the failure with a bare colon.  */
#define UNITY_FAILURE_DETAIL_SEPARATOR ". "

/* Enables TEST_PRINTF.  */
#define UNITY_INCLUDE_PRINT_FORMATTED

/* The generated driver runs the tests, so Unity's default runner, and the
   setUp and tearDown functions it would require, are not needed.  */
#define UNITY_SKIP_DEFAULT_RUNNER

#endif /* GNATTEST_UNITY_CONFIG_H */
