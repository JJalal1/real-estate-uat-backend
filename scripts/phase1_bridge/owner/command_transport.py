"""Read-only fixed GitHub Contents channel. No credential discovery or logging."""
import base64
import hashlib
import json
import re
import urllib.error
import urllib.parse
import urllib.request

import review_protocol as protocol

REPO = protocol.REPOSITORY
BRANCH = 'work/phase1-root-review-20261104'
PREFIX = 'phase1-commands'
MAX_RESPONSE = 96 * 1024
FILE_KEYS = frozenset({'name', 'path', 'sha', 'size', 'url', 'html_url', 'git_url',
                       'download_url', 'type', 'content', 'encoding', '_links'})


class ChannelRefused(RuntimeError):
    pass


def require(value, code):
    if not value:
        raise ChannelRefused(code)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, target):
        return None


class CommandChannel:
    """Only GET the exact run/attempt/sequence path on the compiled branch."""
    def __init__(self, run_id, run_attempt, token, *, opener=None):
        require(type(run_id) is str and re.fullmatch(r'[1-9][0-9]{0,19}', run_id), 'run_id_invalid')
        require(type(run_attempt) is int and 1 <= run_attempt <= 1000, 'run_attempt_invalid')
        require(type(token) is str and 0 < len(token) <= 8192 and '\r' not in token
                and '\n' not in token, 'read_token_invalid')
        self.run_id, self.run_attempt = run_id, run_attempt
        self._token = token
        self._opener = opener or urllib.request.build_opener(NoRedirect())

    def close(self):
        self._token = None

    def path(self, seq):
        require(type(seq) is int and 1 <= seq <= 10000, 'sequence_invalid')
        return f'{PREFIX}/{self.run_id}/{self.run_attempt}/{seq:06d}.json'

    def poll(self, seq):
        require(self._token is not None, 'channel_closed')
        path = self.path(seq)
        url = ('https://api.github.com/repos/' + REPO + '/contents/' + path
               + '?' + urllib.parse.urlencode({'ref': BRANCH}))
        request = urllib.request.Request(url, method='GET', headers={
            'Accept': 'application/vnd.github+json',
            'Authorization': 'Bearer ' + self._token,
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'AQER-Phase1-Fixed-Review-Channel'})
        try:
            with self._opener.open(request, timeout=20) as response:
                require(response.status == 200 and response.geturl() == url, 'unexpected_command_response')
                raw = response.read(MAX_RESPONSE + 1)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            raise ChannelRefused('command_channel_http_failed') from None
        except ChannelRefused:
            raise
        except Exception:
            raise ChannelRefused('command_channel_transport_failed') from None
        require(0 < len(raw) <= MAX_RESPONSE, 'command_response_size_invalid')
        try:
            value = protocol.parse_json(raw, MAX_RESPONSE)
        except protocol.Refused:
            raise ChannelRefused('command_response_json_invalid') from None
        require(set(value) == FILE_KEYS and value['type'] == 'file'
                and value['encoding'] == 'base64' and value['path'] == path
                and value['name'] == path.rsplit('/', 1)[1], 'fixed_command_file_required')
        require(type(value['size']) is int and 0 < value['size'] <= protocol.MAX_ENVELOPE_BYTES
                and type(value['sha']) is str and re.fullmatch(r'[0-9a-f]{40}', value['sha'])
                and type(value['_links']) is dict
                and set(value['_links']) == {'self', 'git', 'html'}, 'command_file_identity_invalid')
        content = value['content']
        require(type(content) is str and len(content) <= protocol.MAX_ENVELOPE_BYTES * 2
                and re.fullmatch(r'[A-Za-z0-9+/=\r\n]+', content), 'command_content_encoding_invalid')
        encoded = content.replace('\r', '').replace('\n', '')
        try:
            data = base64.b64decode(encoded, validate=True)
        except (ValueError, UnicodeError):
            raise ChannelRefused('command_content_encoding_invalid') from None
        require(base64.b64encode(data).decode() == encoded and len(data) == value['size'],
                'command_content_size_mismatch')
        git_blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\x00' + data).hexdigest()
        require(git_blob == value['sha'], 'command_git_blob_mismatch')
        # None of download_url/url/html_url/git_url/_links is ever followed.
        return data
