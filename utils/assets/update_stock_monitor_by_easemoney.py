import base64
import json
import logging
import os
import pickle
import random
import subprocess
import sys
import time
from decimal import Decimal
from typing import List, Type, TypeVar

import ddddocr
import requests
import urllib3
from Crypto.Cipher import PKCS1_v1_5 as PKCS1_cipher
from Crypto.PublicKey import RSA
from pydantic import BaseModel, Field, parse_obj_as

"""
M1 Mac 需要通过 conda 安装 x86 版本的 python
wget https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-MacOSX-x86_64.sh
暂时不支持 python 3.11
"""


class Position(BaseModel):
    """
    持仓
    """

    current_amount: int = Field(alias="Zqsl")
    enable_amount: int = Field(alias="Kysl")
    income_balance: int = 0
    cost_price: Decimal = Field(alias="Cbjg")
    last_price: Decimal = Field(alias="Zxjg")
    # market_value: float = Field(alias="Cbjg")
    stock_code: str = Field(alias="Zqdm")
    stock_name: str = Field(alias="Zqmc")

    @property
    def market_value(self) -> Decimal:
        return self.last_price * self.current_amount

    def update(self, last_price: Decimal):
        self.last_price = last_price


try:
    # noinspection PyUnresolvedReferences
    requests.packages.urllib3.util.ssl_.DEFAULT_CIPHERS = "ALL:@SECLEVEL=1"
    urllib3.disable_warnings()
except Exception as ie:
    print(ie)

logger = logging.getLogger("easy-money")
T = TypeVar("T")


class JywgUrl:
    _BASE = "https://jywg.18.cn/"
    ASSETS = f"{_BASE}Com/GetAssets?validatekey=%s"
    SUBMIT = f"{_BASE}Trade/SubmitTradeV2?validatekey=%s"
    REVOKE = f"{_BASE}Trade/RevokeOrders?validatekey=%s"
    GET_STOCK_LIST = f"{_BASE}Search/GetStockList?validatekey=%s"
    GET_ORDERS_DATA = f"{_BASE}Search/GetOrdersData?validatekey=%s"
    GET_DEAL_DATA = f"{_BASE}Search/GetDealData?validatekey=%s"
    AUTHENTICATION = f"{_BASE}Login/Authentication"
    YZM = f"{_BASE}Login/YZM?randNum="
    AUTHENTICATION_CHECK = f"{_BASE}Trade/Buy"
    GET_HIS_DEAL_DATA = f"{_BASE}Search/GetHisDealData?validatekey=%s"
    GET_HIS_ORDERS_DATA = f"{_BASE}Search/GetHisOrdersData?validatekey=%s"
    GET_CAN_BUY_NEW_STOCK_LIST_V3 = f"{_BASE}Trade/GetCanBuyNewStockListV3?validatekey=%s"
    GET_CONVERTIBLE_BOND_LIST_V2 = f"{_BASE}Trade/GetConvertibleBondListV2?validatekey=%s"
    SUBMIT_BAT_TRADE_V2 = f"{_BASE}Trade/SubmitBatTradeV2?validatekey=%s"


class TradeError(IOError):
    pass


class EastMoneyTrader:
    validate_key = None

    _HEADERS = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; WOW64) "
                      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3239.132 Safari/537.36",
        "Host": "jywg.18.cn",
        "Pragma": "no-cache",
        "Connection": "keep-alive",
        "Accept": "*/*",
        "Accept-Encoding": "gzip, deflate, br",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8,zh-TW;q=0.7",
        "Cache-Control": "no-cache",
        "Referer": "https://jywg.18.cn/Login?el=1&clear=1",
    }

    random_number = "0.9033461201665647898"
    session_file = "/tmp/eastmoney_trader.session"

    def __init__(self, username, password):
        self.username = username
        self.password = self._rsa_password(password)

        if not self._reload_session():
            self.s = requests.Session()
            self.s.verify = False
            self.s.headers.update(self._HEADERS)

    @staticmethod
    def _rsa_password(password):
        public_key = """-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDHdsyxT66pDG4p73yope
7jxA92\nc0AT4qIJ/xtbBcHkFPK77upnsfDTJiVEuQDH+MiMeb+XhCLNKZGp0yaUU6GlxZdp\n+nLW8b7Kmijr3iepaDhcbVTsYB
WchaWUXauj9Lrhz58/6AE/NF0aMolxIGpsi+ST\n2hSHPu3GSXMdhPCkWQIDAQAB\n-----END PUBLIC KEY-----""".encode(
            "utf-8"
        )
        cipher = PKCS1_cipher.new(RSA.import_key(public_key))
        return base64.b64encode(cipher.encrypt(bytes(password.encode("utf8"))))

    def _recognize_verification_code(self, retry=0):
        ocr = ddddocr.DdddOcr(show_ad=False)
        self.random_number = "0.903%d" % random.randint(100000, 900000)
        img_content = self._get_code_image()
        code = ocr.classification(img_content)
        print(f"ocr 验证码:{code}")
        if len(code) == 4:
            return code
        # code length should be 4
        time.sleep(1)
        return self._recognize_verification_code(retry + 1)

    def _get_code_image(self) -> bytes:
        req = self.s.get("%s%s" % (JywgUrl.YZM, self.random_number))
        return req.content

    def _save_session(self):
        """
        save session to a cache file
        """
        # always save (to update timeout)
        with open(self.session_file, "wb") as f:
            pickle.dump((self.validate_key, self.s), f)
            print("updated session cache-file %s" % self.session_file)

    def _reload_session(self):
        if os.path.exists(self.session_file):
            try:
                with open(self.session_file, "rb") as sf:
                    self.validate_key, self.s = pickle.load(sf)
                    return True
            except Exception as e:
                print("load session failed", e)
        return False

    def auto_login(self):
        if self.validate_key:
            try:
                self.get_position()
                print('auto login success')
                return
            except Exception as e:
                print("heartbeat failed, login again")
        print("need login")
        ocr_code_retry_count = 5
        for i in range(ocr_code_retry_count):
            identify_code = self._recognize_verification_code()
            login_res = self.s.post(
                JywgUrl.AUTHENTICATION,
                data={
                    "duration": 1800,
                    "password": self.password,
                    "identifyCode": identify_code,
                    "type": "Z",
                    "userId": self.username,
                    "randNumber": self.random_number,
                },
            ).json()

            if login_res["Status"] != 0:
                logger.info("auto login error, try again later")
                print(login_res)
                time.sleep(3)
            else:
                break

        self._get_valid_key()

        self._save_session()

    def _get_valid_key(self):
        content = self.s.get(JywgUrl.AUTHENTICATION_CHECK).text
        key = 'input id="em_validatekey" type="hidden" value="'
        begin = content.index(key) + len(key)
        end = content.index('" />', begin)
        self.validate_key = content[begin:end]

    def _request_data(self, api: str, params=None, type_: Type[T] = None) -> T:
        api = api % self.validate_key
        result = self.s.get(api, params=params).json()
        # print(api, result)
        if result["Status"] == 0:
            data = result["Data"]
            if not type_:
                return result["Data"]
            return parse_obj_as(type_, data)

        print(result)
        raise TradeError("接口错误")

    @staticmethod
    def _format_time(time_stamp):
        try:
            local_time = time.localtime(time_stamp / 1000)
            return time.strftime("%Y-%m-%d %H:%M:%S", local_time)
        # pylint: disable=broad-except
        except Exception as e:
            return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())

    def get_position(self) -> List[Position]:
        """
        获取持仓
        """
        lst = self._request_data(JywgUrl.GET_STOCK_LIST, type_=List[Position])

        return [i for i in lst if i.current_amount > 0]


# noinspection PyTypeChecker
def main():
    file_name = os.path.expanduser("~/.config/StockMonitor.json")
    if not os.path.exists(file_name):
        print("StockMonitor.json not exists")
        sys.exit(0)

    trader = EastMoneyTrader(os.getenv("EAST_MONEY_USER"), os.getenv("EAST_MONEY_SEC"))
    trader.auto_login()
    pos = trader.get_position()

    pos = [p for p in pos]

    with open(file_name, "r") as f:
        config = json.load(f)
        config_map = {i["code"]: i for i in config}

    rst = list(config_map.values())
    for p in pos:
        c = p.stock_code
        one = config_map.get(c, {"code": p.stock_code})
        one["cost"] = p.cost_price
        one["position"] = p.current_amount

        if c not in config_map:
            if p.current_amount * p.last_price < 1000:
                continue
            rst.append(one)

    pos_map = {p.stock_code: p for p in pos}
    for i in rst:
        if i["position"] > 0 and i["code"] not in pos_map:
            i["position"] = 0
            i["cost"] = 0
            i["showInTitle"] = False
        if i["position"] * i["cost"] > 1000:
            i["showInTitle"] = True

    rst.sort(key=lambda i: i.get("position", 0) * i.get("cost", 0), reverse=True)

    s = json.dumps(rst, indent=4, default=float).encode("utf-8").decode("unicode-escape")
    print(s)

    with open(file_name, "w") as f:
        f.write(s)


if __name__ == '__main__':
    main()
