import 'package:flutter/material.dart';

class CloudStoragePage extends StatefulWidget {
  @override
  _CloudStoragePageState createState() => _CloudStoragePageState();
}

class _CloudStoragePageState extends State<CloudStoragePage> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController(viewportFraction: 0.75);

  final List<Map<String, dynamic>> _plans = [
    {
      'title': '7天滚动存储',
      'price': '￥1',
      'oldPrice': '￥18',
      'save': '立省17元',
      'desc': '连续包月',
      'highlight': true,
      'gradient': [Color(0xFF00B8D4), Color(0xFF4DD0E1)],
    },
    {
      'title': '30天滚动存储',
      'price': '￥18',
      'oldPrice': null,
      'save': null,
      'desc': '月卡',
      'highlight': false,
      'gradient': [Color(0xFF43CEA2), Color(0xFF185A9D)],
    },
    {
      'title': '年卡',
      'price': '￥127',
      'oldPrice': null,
      'save': '立省61元',
      'desc': '年卡',
      'highlight': false,
      'gradient': [Color(0xFFFFB75E), Color(0xFFED8F03)],
    },
  ];

  Matrix4 _getCardTransform(bool isSelected) {
    return isSelected
        ? (Matrix4.identity()..scale(0.8))
        : (Matrix4.identity()..scale(0.7));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Color(0xFF222831) : Color(0xFFF6F9FB);
    final textColor = isDark ? Colors.white : Colors.black87;
    return Scaffold(
      // 不指定backgroundColor，自动跟随主题
      appBar: AppBar(
        title: Text('云存储购买'),
        // 不指定backgroundColor，自动跟随主题
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        titleTextStyle: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 卡片滑动选择区域
              Container(
                height: 200,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  itemCount: _plans.length,
                  itemBuilder: (context, index) {
                    final plan = _plans[index];
                    final isSelected = index == _selectedIndex;
                    return AnimatedContainer(
                      duration: Duration(milliseconds: 350),
                      margin: EdgeInsets.symmetric(horizontal: 2, vertical: isSelected ? 0 : 12),
                      transform: _getCardTransform(isSelected),
                      child: AspectRatio(
                        aspectRatio: 1.0, // 正方形卡片
                        child: _buildPlanCard(
                          context,
                          title: plan['title'],
                          price: plan['price'],
                          oldPrice: plan['oldPrice'],
                          save: plan['save'],
                          desc: plan['desc'],
                          highlight: isSelected,
                          gradient: plan['gradient'],
                          textColor: textColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: 16),
              Text('云存储权益', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              SizedBox(height: 8),
              Center(child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildBenefitItem(Icons.visibility, '天天看护', '事件回看不限时', [Color(0xFF00B8D4), Color(0xFF4DD0E1)]),
                  _buildBenefitItem(Icons.cloud, '云端存储', '离线也能随时看', [Color(0xFF43CEA2), Color(0xFF185A9D)]),
                  _buildBenefitItem(Icons.lock, '数据加密', '金融级加密存储', [Color(0xFFFFB75E), Color(0xFFED8F03)]),
                  _buildBenefitItem(Icons.all_inbox, '无限空间', '存储容量无上限', [Color(0xFF667eea), Color(0xFF764ba2)]),
                ],
              )),
              SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _plans[_selectedIndex]['gradient']),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _plans[_selectedIndex]['gradient'][0].withOpacity(0.18),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    )
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${_plans[_selectedIndex]['price']} ', 
                         style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                    if (_plans[_selectedIndex]['oldPrice'] != null)
                      Text('${_plans[_selectedIndex]['oldPrice']}', 
                           style: TextStyle(fontSize: 16, color: Colors.white70, decoration: TextDecoration.lineThrough)),
                    SizedBox(width: 12),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          )
                        ],
                      ),
                      child: Text('立即支付', style: TextStyle(fontSize: 16, color: _plans[_selectedIndex]['gradient'][0], fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(value: false, onChanged: (v) {}),
                  Expanded(
                    child: Text('已阅读并同意《云存储用户协议》和《云存储自动续费服务协议》', 
                               style: TextStyle(fontSize: 12, color: textColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, {required String title, required String price, String? oldPrice, String? save, required String desc, required bool highlight, required List<Color> gradient, required Color textColor}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: gradient[0].withOpacity(0.25),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                )
              ],
        border: highlight ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (highlight && save != null)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('限时随机立减', style: TextStyle(color: gradient[0], fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            SizedBox(height: 8),
            Text(desc, style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(price, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                if (oldPrice != null) ...[
                  SizedBox(width: 6),
                  Text(oldPrice, style: TextStyle(fontSize: 16, color: Colors.white70, decoration: TextDecoration.lineThrough)),
                ]
              ],
            ),
            if (save != null)
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(save, style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
              ),
            SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String title, String subtitle, List<Color> gradient) {
    return Container(
      width: 120,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withOpacity(0.3),
            blurRadius: 6,
            offset: Offset(0, 3),
          )
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 24, color: Colors.white),
          ),
          SizedBox(height: 8),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
          SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.9))),
        ],
      ),
    );
  }
} 