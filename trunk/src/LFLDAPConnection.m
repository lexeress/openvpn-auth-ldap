/*
 * LFLDAPConnection.m
 * Simple LDAP Wrapper
 *
 * Copyright (c) 2005 Landon Fuller <landonf@threerings.net>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of Landon Fuller nor the names of any contributors
 *    may be used to endorse or promote products derived from this
 *    software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <stdlib.h>
#include <string.h>
#include <err.h>
#include <sys/time.h>

#include "LFLDAPConnection.h"

#include "auth-ldap.h"

static int ldap_get_errno(LDAP *ld) {
	int err;
	if (ldap_get_option(ld, LDAP_OPT_ERROR_NUMBER, &err) != LDAP_OPT_SUCCESS)
		err = LDAP_OTHER;
	return err;
}

static BOOL ldap_set_tls_options(LFAuthLDAPConfig *config) {
	int err;
	int arg;

	if ([config tlsCACertFile]) {
		if ((err = ldap_set_option(NULL, LDAP_OPT_X_TLS_CACERTFILE, [[config tlsCACertFile] cString])) != LDAP_SUCCESS) {
			warnx("Unable to set tlsCACertFile to %s: %d: %s", [[config tlsCACertFile] cString], err, ldap_err2string(err));
			return (false);
		}
        }

	if ([config tlsCACertDir]) {
		if ((err = ldap_set_option(NULL, LDAP_OPT_X_TLS_CACERTDIR, [[config tlsCACertDir] cString])) != LDAP_SUCCESS) {
			warnx("Unable to set tlsCACertDir to %s: %d: %s", [[config tlsCACertDir] cString], err, ldap_err2string(err));
			return (false);
		}
        }

	if ([config tlsCertFile]) {
		if ((err = ldap_set_option(NULL, LDAP_OPT_X_TLS_CERTFILE, [[config tlsCertFile] cString])) != LDAP_SUCCESS) {
			warnx("Unable to set tlsCertFile to %s: %d: %s", [[config tlsCertFile] cString], err, ldap_err2string(err));
			return (false);
		}
        }

	if ([config tlsKeyFile]) {
		if ((err = ldap_set_option(NULL, LDAP_OPT_X_TLS_KEYFILE, [[config tlsKeyFile] cString])) != LDAP_SUCCESS) {
			warnx("Unable to set tlsKeyFile to %s: %d: %s", [[config tlsKeyFile] cString], err, ldap_err2string(err));
			return (false);
		}
        }

	if ([config tlsCipherSuite]) {
		if ((err = ldap_set_option(NULL, LDAP_OPT_X_TLS_CIPHER_SUITE, [[config tlsCipherSuite] cString])) != LDAP_SUCCESS) {
			warnx("Unable to set tlsCipherSuite to %s: %d: %s", [[config tlsCipherSuite] cString], err, ldap_err2string(err));
			return (false);
		}
        }

	/* Always require a valid certificate */	
	arg = LDAP_OPT_X_TLS_HARD;
	if ((err = ldap_set_option(NULL, LDAP_OPT_X_TLS_REQUIRE_CERT, &arg)) != LDAP_SUCCESS) {
		warnx("Unable to set LDAP_OPT_X_TLS_HARD to %d: %d: %s", arg, err, ldap_err2string(err));
		return (false);
	}
	
	return (true);
}

@implementation LFLDAPConnection

+ (BOOL) initGlobalOptionsWithConfig: (LFAuthLDAPConfig *) ldapConfig {
	return (ldap_set_tls_options(ldapConfig));
}

- (id) initWithConfig: (LFAuthLDAPConfig *) ldapConfig {
	struct timeval timeout;
	int arg, err;

	self = [self init];
	if (!self)
		return NULL;

	config = ldapConfig;

	ldap_initialize(&ldapConn, [[config url] cString]);

	if (!ldapConn) {
		warnx("Unable to initialize LDAP server %s", [[config url] cString]);
		[self release];
		return (NULL);
	}

	timeout.tv_sec = [config timeout];
	timeout.tv_usec = 0;

	if (ldap_set_option(ldapConn, LDAP_OPT_NETWORK_TIMEOUT, &timeout) != LDAP_OPT_SUCCESS)
		warnx("Unable to set LDAP network timeout.");

	arg = LDAP_VERSION3;
	if (ldap_set_option(ldapConn, LDAP_OPT_PROTOCOL_VERSION, &arg) != LDAP_OPT_SUCCESS) {
		warnx("Unable to enable LDAPv3.");
		[self release];
		return (NULL);
	}

	if ([config tlsEnabled]) {
		err = ldap_start_tls_s(ldapConn, NULL, NULL);
		if (err != LDAP_SUCCESS) {
			warnx("Unable to enable STARTTLS: %s", ldap_err2string(err));
			[self release];
			return (NULL);
		}
	}

	return (self);
}

- (BOOL) bindWithDN: (const char *) bindDN password: (const char *) password {
	int msgid, err;
	LDAPMessage *res;
	struct berval cred;
	struct timeval timeout;

	/* Set up berval structure for our credentials */
	cred.bv_val = (char *) password;
	cred.bv_len = strlen(password);

	if ((msgid = ldap_sasl_bind_s(ldapConn,
					bindDN,
					LDAP_SASL_SIMPLE,
					&cred,
					NULL,
					NULL,
					NULL)) == -1) {
		err = ldap_get_errno(ldapConn);
		warnx("ldap_bind failed immediately: %s", ldap_err2string(err));
		return (false);
	}

	timeout.tv_sec = [config timeout];
	timeout.tv_usec = 0;

	if (ldap_result(ldapConn, msgid, 1, &timeout, &res) == -1) {
		err = ldap_get_errno(ldapConn);
		if (err == LDAP_TIMEOUT)
			ldap_abandon_ext(ldapConn, msgid, NULL, NULL);
		warnx("ldap_bind failed: %s\n", ldap_err2string(err));
		return (false);
	}

	/* TODO: Provide more diagnostics when a logging API is available */
	ldap_parse_result(ldapConn, res, &err, NULL, NULL, NULL, NULL, 1);
	if (err == LDAP_SUCCESS)
		return (true);

	return (false);
}

- (BOOL) unbind {
	int err;
	err = ldap_unbind_ext_s(ldapConn, NULL, NULL);
	if (err != LDAP_SUCCESS) {
		warnx("Unable to unbind from LDAP server: %s", ldap_err2string(err));
		return (false);
	}
	return (true);
}

@end