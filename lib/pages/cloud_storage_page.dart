import 'package:flutter/material.dart';

class CloudStoragePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Color(0xFF222222) : Colors.white;
    final cardColor = isDark ? Color(0xFF333333) : Color(0xFFF7F7F7);
    final accentColor = isDark ? Color(0xFF00B8D4) : Color(0xFF00B8D4);
    final textColor = isDark ? Colors.white : Colors.black87;
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('云存储购买'),
        backgroundColor: bgColor,
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
              Row(
                children: [
                  Expanded(
                    child: _buildPlanCard(
                      context,
                      title: '7天滚动存储',
                      price: '￥1',
                      oldPrice: '￥18',
                      save: '立省17元',
                      desc: '连续包月',
                      highlight: true,
                      accentColor: accentColor,
                      cardColor: cardColor,
                      textColor: textColor,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _buildPlanCard(
                      context,
                      title: '30天滚动存储',
                      price: '￥18',
                      oldPrice: null,
                      save: null,
                      desc: '月卡',
                      highlight: false,
                      accentColor: accentColor,
                      cardColor: cardColor,
                      textColor: textColor,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _buildPlanCard(
                      context,
                      title: '年卡',
                      price: '￥127',
                      oldPrice: null,
                      save: '立省61元',
                      desc: '年卡',
                      highlight: false,
                      accentColor: accentColor,
                      cardColor: cardColor,
                      textColor: textColor,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              Text('云存储权益', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildBenefitItem(Icons.visibility, '天天看护', '事件回看不限时', textColor),
                  _buildBenefitItem(Icons.cloud, '云端存储', '离线也能随时看', textColor),
                  _buildBenefitItem(Icons.lock, '数据加密', '金融级加密存储', textColor),
                  _buildBenefitItem(Icons.all_inbox, '无限空间', '存储容量无上限', textColor),
                ],
              ),
              SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text('￥1 ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: accentColor)),
                    Text('￥18', style: TextStyle(fontSize: 16, color: textColor, decoration: TextDecoration.lineThrough)),
                    SizedBox(width: 8),
                    Text('立即支付', style: TextStyle(fontSize: 18, color: accentColor)),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(value: false, onChanged: (v) {}),
                  Expanded(
                    child: Text('已阅读并同意《米家云存储用户协议》和《米家云存储自动续费服务协议》', style: TextStyle(fontSize: 13, color: textColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, {required String title, required String price, String? oldPrice, String? save, required String desc, required bool highlight, required Color accentColor, required Color cardColor, required Color textColor}) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? accentColor.withOpacity(0.1) : cardColor,
        borderRadius: BorderRadius.circular(12),
        border: highlight ? Border.all(color: accentColor, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (highlight && save != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('限时随机立减', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          SizedBox(height: 8),
          Text(desc, style: TextStyle(fontSize: 14, color: accentColor)),
          SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
              if (oldPrice != null) ...[
                SizedBox(width: 6),
                Text(oldPrice, style: TextStyle(fontSize: 16, color: textColor, decoration: TextDecoration.lineThrough)),
              ]
            ],
          ),
          if (save != null)
            Text(save, style: TextStyle(fontSize: 13, color: accentColor)),
          SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 15, color: textColor)),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String title, String subtitle, Color textColor) {
    return Container(
      width: 140,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: textColor.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: textColor),
          SizedBox(height: 8),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
          SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.7))),
        ],
      ),
    );
  }
} 