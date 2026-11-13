// 田宫官网目录增补数据：2026-11-13 按漆系核对，来源见 docs/tamiya-catalog-coverage.json。
// 只补充原目录缺项；原有商品和历史 RGB 继续由 PaintCatalog 保留，以兼容旧配方。
// 色样取自官方 2024 色卡，与当前商品目录逐色对应，不虚构连续色号。
import Foundation

/// 独立维护田宫增补表，色号和色样仍通过统一的目录与来源索引读取。
enum TamiyaPaintAdditions {
    /// tamiyaAcrylic 的新增商品；字段依次为色号、中文名、英文名和初始预览 HEX。
    static let acrylic = """
X-3|宝蓝|Royal Blue|163560
X-10|枪铁色|Gun Metal|595757
X-11|铬银|Chrome Silver|D7D8D8
X-12|金箔色|Gold Leaf|CDA700
X-13|金属蓝|Metallic Blue|00618A
X-19|烟色|Smoke|C7C8C8
X-23|透明蓝|Clear Blue|00A6EA
X-24|透明黄|Clear Yellow|FFE500
X-25|透明绿|Clear Green|009E41
X-26|透明橙|Clear Orange|EF7E00
X-27|透明红|Clear Red|E60039
X-28|公园绿|Park Green|009944
X-31|钛金|Titanium Gold|DDCBA5
X-32|钛银|Titanium Silver|DFDECF
X-33|青铜|Bronze|877575
X-34|金属棕|Metallic Brown|C05608
XF-6|铜色|Copper|C54E27
XF-11|日本海军绿|J.N. Green|00473A
XF-12|日本海军灰|J.N. Grey|CAD2C3
XF-13|日本陆军绿|J.A. Green|014542
XF-14|日本陆军灰|J.A. Grey|EEECD9
XF-16|消光铝色|Flat Aluminum|B7B8B8
XF-17|海蓝|Sea Blue|103A58
XF-20|中灰|Medium Grey|B1BCB7
XF-21|天空色|Sky|E9F1CD
XF-22|RLM 灰|RLM Grey|526367
XF-23|浅蓝|Light Blue|7ECCDE
XF-25|浅海灰|Light Sea Grey|859BA6
XF-26|深绿|Deep Green|0C6441
XF-27|黑绿|Black Green|004731
XF-28|深铜色|Dark Copper|A58063
XF-50|原野蓝|Field Blue|0C82A6
XF-51|卡其褐|Khaki Drab|575F5C
XF-54|深海灰|Dark Sea Grey|ACB2B4
XF-56|金属灰|Metallic Grey|727172
XF-61|深绿|Dark Green|004731
XF-70|日本海军深绿 2|Dark Green 2 (IJN)|004234
XF-71|日本海军座舱绿|Cockpit Green (IJN)|759875
XF-72|陆自棕|Brown (JGSDF)|7F5C2E
XF-73|陆自深绿|Dark Green (JGSDF)|1A603A
XF-74|陆自橄榄褐|Olive Drab (JGSDF)|275538
XF-75|吴海军工厂灰|IJN Gray (Kure Arsenal)|717C85
XF-76|日本海军灰绿|Gray Green (IJN)|B9C4A8
XF-77|佐世保海军工厂灰|IJN Gray (Sasebo Arsenal)|535860
XF-78|木甲板棕|Wooden Deck Tan|BFB086
XF-79|油毡甲板棕|Linoleum Deck Brown|5E4A33
XF-80|皇家浅灰|Royal Light Gray|C1CBC9
XF-81|英国空军深绿 2|Dark Green 2 (RAF)|365633
XF-82|英国空军海洋灰 2|Ocean Gray 2 (RAF)|6D8E9B
XF-83|英国空军中海灰 2|Medium Sea Gray 2 (RAF)|ABBFBB
XF-84|暗铁色（履带色）|Dark Iron|524333
XF-85|橡胶黑|Rubber Black|231916
XF-87|舞鹤海军工厂灰|IJN Gray (Maizuru Arsenal)|7E8186
XF-88|德国陆军深黄 2|Dark Yellow 2|C9B54C
XF-89|德国陆军深绿 2|Dark Green 2|5C8461
XF-90|德国陆军红棕 2|Red Brown 2|4F3833
XF-91|横须贺海军工厂灰|IJN Gray (Yokosuka Arsenal)|646C75
XF-92|黄棕（非洲军团 1941）|Yellow-Brown (DAK 1941)|B38351
XF-93|浅棕（非洲军团 1942）|Light Brown (DAK 1942)|E7B36E
"""

    /// tamiyaEnamel 的新增商品；字段依次为色号、中文名、英文名和初始预览 HEX。
    static let enamel = """
X-3|宝蓝|Royal Blue|163560
X-10|枪铁色|Gun Metal|595757
X-11|铬银|Chrome Silver|D7D8D8
X-12|金箔色|Gold Leaf|CDA700
X-13|金属蓝|Metallic Blue|00618A
X-19|烟色|Smoke|C7C8C8
X-23|透明蓝|Clear Blue|00A6EA
X-24|透明黄|Clear Yellow|FFE500
X-25|透明绿|Clear Green|009E41
X-26|透明橙|Clear Orange|EF7E00
X-27|透明红|Clear Red|E60039
X-28|公园绿|Park Green|009944
X-31|钛金|Titanium Gold|DDCBA5
X-32|钛银|Titanium Silver|DFDECF
X-33|青铜|Bronze|877575
X-34|金属棕|Metallic Brown|C05608
XF-6|铜色|Copper|C54E27
XF-11|日本海军绿|J.N. Green|00473A
XF-12|日本海军灰|J.N. Grey|CAD2C3
XF-13|日本陆军绿|J.A. Green|014542
XF-14|日本陆军灰|J.A. Grey|EEECD9
XF-16|消光铝色|Flat Aluminum|B7B8B8
XF-17|海蓝|Sea Blue|103A58
XF-20|中灰|Medium Grey|B1BCB7
XF-21|天空色|Sky|E9F1CD
XF-22|RLM 灰|RLM Grey|526367
XF-23|浅蓝|Light Blue|7ECCDE
XF-25|浅海灰|Light Sea Grey|859BA6
XF-26|深绿|Deep Green|0C6441
XF-27|黑绿|Black Green|004731
XF-28|深铜色|Dark Copper|A58063
XF-50|原野蓝|Field Blue|0C82A6
XF-51|卡其褐|Khaki Drab|575F5C
XF-54|深海灰|Dark Sea Grey|ACB2B4
XF-56|金属灰|Metallic Grey|727172
XF-61|深绿|Dark Green|004731
XF-70|日本海军深绿 2|Dark Green 2 (IJN)|004234
XF-71|日本海军座舱绿|Cockpit Green (IJN)|759875
XF-84|暗铁色（履带色）|Dark Iron|524333
XF-85|橡胶黑|Rubber Black|231916
"""

    /// tamiyaLacquer 的新增商品；字段依次为色号、中文名、英文名和初始预览 HEX。
    static let lacquer = """
LP-11|银色|Silver|DFDFDF
LP-19|枪铁色|Gun Metal|595757
LP-20|浅枪铁色|Light Gun Metal|898989
LP-38|消光铝色|Flat Aluminum|DCDDDD
LP-40|金属黑|Metallic Black|3F3B3A
LP-41|云母蓝|Mica Blue|00398E
LP-42|云母红|Mica Red|C8171E
LP-43|珍珠白|Pearl White|FFFFFF
LP-44|金属橙|Metallic Orange|EE7800
LP-45|赛车蓝|Racing Blue|003C90
LP-46|纯金属红|Pure Metallic Red|DF0011
LP-47|珠光蓝|Pearl Blue|003C90
LP-48|闪亮银|Sparkling Silver|DFDFDF
LP-52|透明红|Clear Red|E60039
LP-53|透明橙|Clear Orange|F18900
LP-54|暗铁色（履带色）|Dark Iron|524333
LP-55|德国陆军深黄 2|Dark Yellow 2|C9B54C
LP-56|德国陆军深绿 2|Dark Green 2|5C8461
LP-57|德国陆军红棕 2|Red Brown 2|4F3833
LP-58|北约绿|NATO Green|275538
LP-59|北约棕|NATO Brown|6A4B31
LP-60|北约黑|NATO Black|231916
LP-61|金属灰|Metallic Gray|727172
LP-62|钛金|Titanium Gold|DBCA94
LP-63|钛银|Titanium Silver|DDDCCF
LP-64|陆自橄榄褐|Olive Drab (JGSDF)|275538
LP-65|橡胶黑|Rubber Black|231916
LP-66|消光肤色|Flat Flesh|FACE90
LP-67|烟色|Smoke|C7C8C8
LP-68|透明蓝|Clear Blue|00A6EA
LP-69|透明黄|Clear Yellow|FFE500
LP-70|亮光铝色|Gloss Aluminum|DCDDDD
LP-71|香槟金|Champagne Gold|D2C89B
LP-72|云母银|Mica Silver|D4D9DC
LP-73|卡其|Khaki|9B9033
LP-74|土棕|Flat Earth|994930
LP-75|米黄|Buff|CBA77C
LP-76|黄棕（非洲军团 1941）|Yellow-Brown (DAK 1941)|B38351
LP-77|浅棕（非洲军团 1942）|Light Brown (DAK 1942)|E7B36E
LP-78|消光蓝|Flat Blue|006995
LP-79|消光红|Flat Red|E6001D
LP-80|消光黄|Flat Yellow|FFE200
LP-81|调色蓝|Mixing Blue|1F2B66
LP-82|调色红|Mixing Red|C8123D
LP-83|调色黄|Mixing Yellow|FED800
LP-84|迷彩灰|Camouflage Gray|6F6F6F
LP-85|中空灰|Medium Air Gray|848484
"""

    /// tamiyaAircraft 的新增商品；字段依次为色号、中文名、英文名和初始预览 HEX。
    static let aircraft = """
AS-1|日本海军深绿|Dark Green (IJN)|234945
AS-2|日本海军浅灰|Light Gray (IJN)|A4ACA9
AS-3|德国空军灰绿|Gray Green (Luftwaffe)|285961
AS-4|德国空军灰紫|Gray Violet (Luftwaffe)|374952
AS-5|德国空军浅蓝|Light Blue (Luftwaffe)|8EB5B8
AS-6|橄榄褐|Olive Drab|4A5E3D
AS-7|中性灰|Neutral Gray|96A0A6
AS-8|海军蓝|Navy Blue|003686
AS-9|英国空军深绿|Dark Green (RAF)|4A5434
AS-10|英国空军海洋灰|Ocean Grey (RAF)|8598AB
AS-11|英国空军中海灰|Medium Sea Grey (RAF)|BABCAA
AS-12|裸金属银|Bare-Metal Silver|C9CACB
AS-13|绿色|Green|364E3B
AS-14|橄榄绿|Olive Green|446140
AS-15|棕褐色|Tan|BC9967
AS-16|浅灰|Light Gray|D1CEC1
AS-17|日本陆军深绿|Dark Green(IJA)|0D5E4C
AS-18|日本陆军浅灰|Light Gray(IJA)|A7B6B5
AS-19|中间蓝|Intermediate Blue|5A9AB7
AS-20|识别白|Insignia White|DDDCD7
AS-21|日本海军深绿 2|Dark Green 2 (IJN)|004234
AS-22|深土棕|Dark Earth|7E5C52
AS-23|德国空军浅绿|Light Green (Luftwaffe)|3C6A34
AS-24|德国空军深绿|Dark Green (Luftwaffe)|254F34
AS-25|深幽灵灰|Dark Ghost Grey|80A1B1
AS-26|浅幽灵灰|Light Ghost Grey|98B4C2
AS-27|炮舰灰 2|Gunship Gray 2|8DA0AA
AS-28|中灰|Medium Gray|8DA0AA
AS-29|日本海军灰绿|Gray Green (IJN)|B9C4A8
AS-30|英国空军深绿 2|Dark Green 2 (RAF)|365633
AS-31|英国空军海洋灰 2|Ocean Gray 2 (RAF)|6D8E9B
AS-32|英国空军中海灰 2|Medium Sea Gray 2 (RAF)|ABBFBB
AS-33|迷彩灰|Camouflage Gray|6F6F6F
"""

    /// tamiyaPolycarbonate 的新增商品；字段依次为色号、中文名、英文名和初始预览 HEX。
    static let polycarbonate = """
69944|PS 深蓝（特别企划）|PS Dark Blue (Special Edition)|002F55
PS-1|白色|White|FFFFFF
PS-2|红色|Red|E60013
PS-3|浅蓝|Light Blue|00A5EA
PS-4|蓝色|Blue|004098
PS-5|黑色|Black|231916
PS-6|黄色|Yellow|FFF100
PS-7|橙色|Orange|EF7A00
PS-8|浅绿|Light Green|5DB531
PS-9|绿色|Green|004B33
PS-10|紫色|Purple|734698
PS-11|粉红|Pink|F1A1C4
PS-12|银色|Silver|D5D5D6
PS-13|金色|Gold|ECBC00
PS-14|铜色|Copper|CC5D17
PS-15|金属红|Metallic Red|E60013
PS-16|金属蓝|Metallic Blue|0069B7
PS-17|金属绿|Metallic Green|008442
PS-18|金属紫|Metallic Purple|494992
PS-19|骆驼黄|Camel Yellow|FBC600
PS-20|荧光红|Fluorescent Red|E60013
PS-21|公园绿|Park Green|009944
PS-22|赛车绿|Racing Green|007447
PS-23|枪铁色|Gun Metal|575555
PS-24|荧光橙|Fluorescent Orange|E94B2B
PS-25|亮绿|Bright Green|007F55
PS-27|荧光黄|Fluorescent Yellow|FFF100
PS-28|荧光绿|Fluorescent Green|9EC914
PS-29|荧光粉红|Fluorescent Pink|EB6BA4
PS-30|鲜亮蓝|Brilliant Blue|006EB7
PS-31|烟色|Smoke|C8BEC3
PS-32|科尔萨灰|Corsa Gray|B3D3DB
PS-33|樱桃红|Cherry Red|D5004D
PS-34|亮红|Bright Red|E60013
PS-35|蓝紫|Blue Violet|5977BA
PS-36|半透明银|Translucent Silver|DCDDDD
PS-37|半透明红|Translucent Red|C8123D
PS-38|半透明蓝|Translucent Blue|0B5FAD
PS-39|半透明浅蓝|Translucent Light Blue|00A5EA
PS-40|半透明粉红|Translucent Pink|F1A1C4
PS-41|亮银|Bright Silver|CCD1D4
PS-42|半透明黄|Translucent Yellow|FFF100
PS-43|半透明橙|Translucent Orange|F08300
PS-44|半透明绿|Translucent Green|00A151
PS-45|半透明紫|Translucent Purple|584C9D
PS-46|变色紫／绿|Iridescent Purple/Green|D5DAD4
PS-47|变色粉红／金|Iridescent Pink/Gold|E1D7BC
PS-48|半光阳极氧化银|Semi-Gloss Silver Anodized Aluminum|DDE3E6
PS-49|阳极氧化天蓝|Sky Blue Anodized Aluminum|96C6E3
PS-50|闪亮阳极氧化粉红|Sparkling Pink Anodized Aluminum|D5A3C2
PS-51|阳极氧化紫|Purple Anodized Aluminum|858ABD
PS-52|阳极氧化香槟金|Champagne Gold Anodized Aluminum|D6C677
PS-54|钴绿|Cobalt Green|00A497
PS-56|芥末黄|Mustard Yellow|D5B200
PS-57|珍珠白|Pearl White|FFFFFF
PS-59|深金属蓝|Dark Metallic Blue|003175
PS-60|亮云母红|Bright Mica Red|E60013
PS-61|金属橙|Metallic Orange|E17B00
PS-62|纯橙|Pure Orange|F18D00
PS-63|亮枪铁色|Bright Gun Metal|828D93
"""

    /// 新增商品的官方色卡取样；逐项坐标和文件哈希记录于 paint-swatch-sources.json。
    static let swatches = """
tamiyaAcrylic|X-3|163560|tamiyaChart
tamiyaAcrylic|X-10|595757|tamiyaChart
tamiyaAcrylic|X-11|D7D8D8|tamiyaChart
tamiyaAcrylic|X-12|CDA700|tamiyaChart
tamiyaAcrylic|X-13|00618A|tamiyaChart
tamiyaAcrylic|X-19|C7C8C8|tamiyaChart
tamiyaAcrylic|X-23|00A6EA|tamiyaChart
tamiyaAcrylic|X-24|FFE500|tamiyaChart
tamiyaAcrylic|X-25|009E41|tamiyaChart
tamiyaAcrylic|X-26|EF7E00|tamiyaChart
tamiyaAcrylic|X-27|E60039|tamiyaChart
tamiyaAcrylic|X-28|009944|tamiyaChart
tamiyaAcrylic|X-31|DDCBA5|tamiyaChart
tamiyaAcrylic|X-32|DFDECF|tamiyaChart
tamiyaAcrylic|X-33|877575|tamiyaChart
tamiyaAcrylic|X-34|C05608|tamiyaChart
tamiyaAcrylic|XF-6|C54E27|tamiyaChart
tamiyaAcrylic|XF-11|00473A|tamiyaChart
tamiyaAcrylic|XF-12|CAD2C3|tamiyaChart
tamiyaAcrylic|XF-13|014542|tamiyaChart
tamiyaAcrylic|XF-14|EEECD9|tamiyaChart
tamiyaAcrylic|XF-16|B7B8B8|tamiyaChart
tamiyaAcrylic|XF-17|103A58|tamiyaChart
tamiyaAcrylic|XF-20|B1BCB7|tamiyaChart
tamiyaAcrylic|XF-21|E9F1CD|tamiyaChart
tamiyaAcrylic|XF-22|526367|tamiyaChart
tamiyaAcrylic|XF-23|7ECCDE|tamiyaChart
tamiyaAcrylic|XF-25|859BA6|tamiyaChart
tamiyaAcrylic|XF-26|0C6441|tamiyaChart
tamiyaAcrylic|XF-27|004731|tamiyaChart
tamiyaAcrylic|XF-28|A58063|tamiyaChart
tamiyaAcrylic|XF-50|0C82A6|tamiyaChart
tamiyaAcrylic|XF-51|575F5C|tamiyaChart
tamiyaAcrylic|XF-54|ACB2B4|tamiyaChart
tamiyaAcrylic|XF-56|727172|tamiyaChart
tamiyaAcrylic|XF-61|004731|tamiyaChart
tamiyaAcrylic|XF-70|004234|tamiyaChart
tamiyaAcrylic|XF-71|759875|tamiyaChart
tamiyaAcrylic|XF-72|7F5C2E|tamiyaChart
tamiyaAcrylic|XF-73|1A603A|tamiyaChart
tamiyaAcrylic|XF-74|275538|tamiyaChart
tamiyaAcrylic|XF-75|717C85|tamiyaChart
tamiyaAcrylic|XF-76|B9C4A8|tamiyaChart
tamiyaAcrylic|XF-77|535860|tamiyaChart
tamiyaAcrylic|XF-78|BFB086|tamiyaChart
tamiyaAcrylic|XF-79|5E4A33|tamiyaChart
tamiyaAcrylic|XF-80|C1CBC9|tamiyaChart
tamiyaAcrylic|XF-81|365633|tamiyaChart
tamiyaAcrylic|XF-82|6D8E9B|tamiyaChart
tamiyaAcrylic|XF-83|ABBFBB|tamiyaChart
tamiyaAcrylic|XF-84|524333|tamiyaChart
tamiyaAcrylic|XF-85|231916|tamiyaChart
tamiyaAcrylic|XF-87|7E8186|tamiyaChart
tamiyaAcrylic|XF-88|C9B54C|tamiyaChart
tamiyaAcrylic|XF-89|5C8461|tamiyaChart
tamiyaAcrylic|XF-90|4F3833|tamiyaChart
tamiyaAcrylic|XF-91|646C75|tamiyaChart
tamiyaAcrylic|XF-92|B38351|tamiyaChart
tamiyaAcrylic|XF-93|E7B36E|tamiyaChart
tamiyaEnamel|X-3|163560|tamiyaChart
tamiyaEnamel|X-10|595757|tamiyaChart
tamiyaEnamel|X-11|D7D8D8|tamiyaChart
tamiyaEnamel|X-12|CDA700|tamiyaChart
tamiyaEnamel|X-13|00618A|tamiyaChart
tamiyaEnamel|X-19|C7C8C8|tamiyaChart
tamiyaEnamel|X-23|00A6EA|tamiyaChart
tamiyaEnamel|X-24|FFE500|tamiyaChart
tamiyaEnamel|X-25|009E41|tamiyaChart
tamiyaEnamel|X-26|EF7E00|tamiyaChart
tamiyaEnamel|X-27|E60039|tamiyaChart
tamiyaEnamel|X-28|009944|tamiyaChart
tamiyaEnamel|X-31|DDCBA5|tamiyaChart
tamiyaEnamel|X-32|DFDECF|tamiyaChart
tamiyaEnamel|X-33|877575|tamiyaChart
tamiyaEnamel|X-34|C05608|tamiyaChart
tamiyaEnamel|XF-6|C54E27|tamiyaChart
tamiyaEnamel|XF-11|00473A|tamiyaChart
tamiyaEnamel|XF-12|CAD2C3|tamiyaChart
tamiyaEnamel|XF-13|014542|tamiyaChart
tamiyaEnamel|XF-14|EEECD9|tamiyaChart
tamiyaEnamel|XF-16|B7B8B8|tamiyaChart
tamiyaEnamel|XF-17|103A58|tamiyaChart
tamiyaEnamel|XF-20|B1BCB7|tamiyaChart
tamiyaEnamel|XF-21|E9F1CD|tamiyaChart
tamiyaEnamel|XF-22|526367|tamiyaChart
tamiyaEnamel|XF-23|7ECCDE|tamiyaChart
tamiyaEnamel|XF-25|859BA6|tamiyaChart
tamiyaEnamel|XF-26|0C6441|tamiyaChart
tamiyaEnamel|XF-27|004731|tamiyaChart
tamiyaEnamel|XF-28|A58063|tamiyaChart
tamiyaEnamel|XF-50|0C82A6|tamiyaChart
tamiyaEnamel|XF-51|575F5C|tamiyaChart
tamiyaEnamel|XF-54|ACB2B4|tamiyaChart
tamiyaEnamel|XF-56|727172|tamiyaChart
tamiyaEnamel|XF-61|004731|tamiyaChart
tamiyaEnamel|XF-70|004234|tamiyaChart
tamiyaEnamel|XF-71|759875|tamiyaChart
tamiyaEnamel|XF-84|524333|tamiyaChart
tamiyaEnamel|XF-85|231916|tamiyaChart
tamiyaLacquer|LP-11|DFDFDF|tamiyaChart
tamiyaLacquer|LP-19|595757|tamiyaChart
tamiyaLacquer|LP-20|898989|tamiyaChart
tamiyaLacquer|LP-38|DCDDDD|tamiyaChart
tamiyaLacquer|LP-40|3F3B3A|tamiyaChart
tamiyaLacquer|LP-41|00398E|tamiyaChart
tamiyaLacquer|LP-42|C8171E|tamiyaChart
tamiyaLacquer|LP-43|FFFFFF|tamiyaChart
tamiyaLacquer|LP-44|EE7800|tamiyaChart
tamiyaLacquer|LP-45|003C90|tamiyaChart
tamiyaLacquer|LP-46|DF0011|tamiyaChart
tamiyaLacquer|LP-47|003C90|tamiyaChart
tamiyaLacquer|LP-48|DFDFDF|tamiyaChart
tamiyaLacquer|LP-52|E60039|tamiyaChart
tamiyaLacquer|LP-53|F18900|tamiyaChart
tamiyaLacquer|LP-54|524333|tamiyaChart
tamiyaLacquer|LP-55|C9B54C|tamiyaChart
tamiyaLacquer|LP-56|5C8461|tamiyaChart
tamiyaLacquer|LP-57|4F3833|tamiyaChart
tamiyaLacquer|LP-58|275538|tamiyaChart
tamiyaLacquer|LP-59|6A4B31|tamiyaChart
tamiyaLacquer|LP-60|231916|tamiyaChart
tamiyaLacquer|LP-61|727172|tamiyaChart
tamiyaLacquer|LP-62|DBCA94|tamiyaChart
tamiyaLacquer|LP-63|DDDCCF|tamiyaChart
tamiyaLacquer|LP-64|275538|tamiyaChart
tamiyaLacquer|LP-65|231916|tamiyaChart
tamiyaLacquer|LP-66|FACE90|tamiyaChart
tamiyaLacquer|LP-67|C7C8C8|tamiyaChart
tamiyaLacquer|LP-68|00A6EA|tamiyaChart
tamiyaLacquer|LP-69|FFE500|tamiyaChart
tamiyaLacquer|LP-70|DCDDDD|tamiyaChart
tamiyaLacquer|LP-71|D2C89B|tamiyaChart
tamiyaLacquer|LP-72|D4D9DC|tamiyaChart
tamiyaLacquer|LP-73|9B9033|tamiyaChart
tamiyaLacquer|LP-74|994930|tamiyaChart
tamiyaLacquer|LP-75|CBA77C|tamiyaChart
tamiyaLacquer|LP-76|B38351|tamiyaChart
tamiyaLacquer|LP-77|E7B36E|tamiyaChart
tamiyaLacquer|LP-78|006995|tamiyaChart
tamiyaLacquer|LP-79|E6001D|tamiyaChart
tamiyaLacquer|LP-80|FFE200|tamiyaChart
tamiyaLacquer|LP-81|1F2B66|tamiyaChart
tamiyaLacquer|LP-82|C8123D|tamiyaChart
tamiyaLacquer|LP-83|FED800|tamiyaChart
tamiyaLacquer|LP-84|6F6F6F|tamiyaChart
tamiyaLacquer|LP-85|848484|tamiyaChart
tamiyaAircraft|AS-1|234945|tamiyaChart
tamiyaAircraft|AS-2|A4ACA9|tamiyaChart
tamiyaAircraft|AS-3|285961|tamiyaChart
tamiyaAircraft|AS-4|374952|tamiyaChart
tamiyaAircraft|AS-5|8EB5B8|tamiyaChart
tamiyaAircraft|AS-6|4A5E3D|tamiyaChart
tamiyaAircraft|AS-7|96A0A6|tamiyaChart
tamiyaAircraft|AS-8|003686|tamiyaChart
tamiyaAircraft|AS-9|4A5434|tamiyaChart
tamiyaAircraft|AS-10|8598AB|tamiyaChart
tamiyaAircraft|AS-11|BABCAA|tamiyaChart
tamiyaAircraft|AS-12|C9CACB|tamiyaChart
tamiyaAircraft|AS-13|364E3B|tamiyaChart
tamiyaAircraft|AS-14|446140|tamiyaChart
tamiyaAircraft|AS-15|BC9967|tamiyaChart
tamiyaAircraft|AS-16|D1CEC1|tamiyaChart
tamiyaAircraft|AS-17|0D5E4C|tamiyaChart
tamiyaAircraft|AS-18|A7B6B5|tamiyaChart
tamiyaAircraft|AS-19|5A9AB7|tamiyaChart
tamiyaAircraft|AS-20|DDDCD7|tamiyaChart
tamiyaAircraft|AS-21|004234|tamiyaChart
tamiyaAircraft|AS-22|7E5C52|tamiyaChart
tamiyaAircraft|AS-23|3C6A34|tamiyaChart
tamiyaAircraft|AS-24|254F34|tamiyaChart
tamiyaAircraft|AS-25|80A1B1|tamiyaChart
tamiyaAircraft|AS-26|98B4C2|tamiyaChart
tamiyaAircraft|AS-27|8DA0AA|tamiyaChart
tamiyaAircraft|AS-28|8DA0AA|tamiyaChart
tamiyaAircraft|AS-29|B9C4A8|tamiyaChart
tamiyaAircraft|AS-30|365633|tamiyaChart
tamiyaAircraft|AS-31|6D8E9B|tamiyaChart
tamiyaAircraft|AS-32|ABBFBB|tamiyaChart
tamiyaAircraft|AS-33|6F6F6F|tamiyaChart
tamiyaPolycarbonate|69944|002F55|tamiyaChart
tamiyaPolycarbonate|PS-1|FFFFFF|tamiyaChart
tamiyaPolycarbonate|PS-2|E60013|tamiyaChart
tamiyaPolycarbonate|PS-3|00A5EA|tamiyaChart
tamiyaPolycarbonate|PS-4|004098|tamiyaChart
tamiyaPolycarbonate|PS-5|231916|tamiyaChart
tamiyaPolycarbonate|PS-6|FFF100|tamiyaChart
tamiyaPolycarbonate|PS-7|EF7A00|tamiyaChart
tamiyaPolycarbonate|PS-8|5DB531|tamiyaChart
tamiyaPolycarbonate|PS-9|004B33|tamiyaChart
tamiyaPolycarbonate|PS-10|734698|tamiyaChart
tamiyaPolycarbonate|PS-11|F1A1C4|tamiyaChart
tamiyaPolycarbonate|PS-12|D5D5D6|tamiyaChart
tamiyaPolycarbonate|PS-13|ECBC00|tamiyaChart
tamiyaPolycarbonate|PS-14|CC5D17|tamiyaChart
tamiyaPolycarbonate|PS-15|E60013|tamiyaChart
tamiyaPolycarbonate|PS-16|0069B7|tamiyaChart
tamiyaPolycarbonate|PS-17|008442|tamiyaChart
tamiyaPolycarbonate|PS-18|494992|tamiyaChart
tamiyaPolycarbonate|PS-19|FBC600|tamiyaChart
tamiyaPolycarbonate|PS-20|E60013|tamiyaChart
tamiyaPolycarbonate|PS-21|009944|tamiyaChart
tamiyaPolycarbonate|PS-22|007447|tamiyaChart
tamiyaPolycarbonate|PS-23|575555|tamiyaChart
tamiyaPolycarbonate|PS-24|E94B2B|tamiyaChart
tamiyaPolycarbonate|PS-25|007F55|tamiyaChart
tamiyaPolycarbonate|PS-27|FFF100|tamiyaChart
tamiyaPolycarbonate|PS-28|9EC914|tamiyaChart
tamiyaPolycarbonate|PS-29|EB6BA4|tamiyaChart
tamiyaPolycarbonate|PS-30|006EB7|tamiyaChart
tamiyaPolycarbonate|PS-31|C8BEC3|tamiyaChart
tamiyaPolycarbonate|PS-32|B3D3DB|tamiyaChart
tamiyaPolycarbonate|PS-33|D5004D|tamiyaChart
tamiyaPolycarbonate|PS-34|E60013|tamiyaChart
tamiyaPolycarbonate|PS-35|5977BA|tamiyaChart
tamiyaPolycarbonate|PS-36|DCDDDD|tamiyaChart
tamiyaPolycarbonate|PS-37|C8123D|tamiyaChart
tamiyaPolycarbonate|PS-38|0B5FAD|tamiyaChart
tamiyaPolycarbonate|PS-39|00A5EA|tamiyaChart
tamiyaPolycarbonate|PS-40|F1A1C4|tamiyaChart
tamiyaPolycarbonate|PS-41|CCD1D4|tamiyaChart
tamiyaPolycarbonate|PS-42|FFF100|tamiyaChart
tamiyaPolycarbonate|PS-43|F08300|tamiyaChart
tamiyaPolycarbonate|PS-44|00A151|tamiyaChart
tamiyaPolycarbonate|PS-45|584C9D|tamiyaChart
tamiyaPolycarbonate|PS-46|D5DAD4|tamiyaChart
tamiyaPolycarbonate|PS-47|E1D7BC|tamiyaChart
tamiyaPolycarbonate|PS-48|DDE3E6|tamiyaChart
tamiyaPolycarbonate|PS-49|96C6E3|tamiyaChart
tamiyaPolycarbonate|PS-50|D5A3C2|tamiyaChart
tamiyaPolycarbonate|PS-51|858ABD|tamiyaChart
tamiyaPolycarbonate|PS-52|D6C677|tamiyaChart
tamiyaPolycarbonate|PS-54|00A497|tamiyaChart
tamiyaPolycarbonate|PS-56|D5B200|tamiyaChart
tamiyaPolycarbonate|PS-57|FFFFFF|tamiyaChart
tamiyaPolycarbonate|PS-59|003175|tamiyaChart
tamiyaPolycarbonate|PS-60|E60013|tamiyaChart
tamiyaPolycarbonate|PS-61|E17B00|tamiyaChart
tamiyaPolycarbonate|PS-62|F18D00|tamiyaChart
tamiyaPolycarbonate|PS-63|828D93|tamiyaChart
"""
}
