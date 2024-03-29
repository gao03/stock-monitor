## 截图
![img.png](img.png)

## 功能说明


## 配置说明

| 字段                |   类型   | 是否必填 |   示例   |                      说明                       |
|-------------------|:------:|:----:|:------:|:---------------------------------------------:|
| code              | string |  是   | 000001 |                     股票代码                      |
| type              |  int   |  否   |   1    | 股票类型<br/>0-深A, 1-沪A, 105-美股1, 106-美股2, 116-港股 |
| cost              |  int   |  否   |   1    |                     持仓成本                      |
| position          |  int   |  否   |  100   |                     持仓数量                      |
| name              | string |  否   |  上证指数  |                     股票名称                      |   
| showInTitle       |  bool  |  否   |  true  |               是否展示在菜单栏，默认 true                |
| enableRealTimePic |  bool  |  否   |  true  |             是否启用实时信息图片，默认 false。              |

示例：
```json
[
  {
    "code": "000001",
    "type": 1,
    "cost": 0,
    "position": 0,
    "name": "上证指数",
    "showInTitle": true,
    "enableRealTimePic": true
  }
]
```