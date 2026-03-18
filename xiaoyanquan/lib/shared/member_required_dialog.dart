import 'package:flutter/material.dart';

/// 通用"开通会员"提示弹窗
/// 显示客服二维码，引导用户扫码开通会员
class MemberRequiredDialog {
  static const String _qrAsset =
      'assets/images/covers/membership_service_qr.jpg';

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          title: const Row(
            children: [
              Icon(Icons.workspace_premium_rounded,
                  color: Color(0xFFE13D6E), size: 22),
              SizedBox(width: 8),
              Text(
                '开通会员',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '该功能仅限会员使用\n请扫码联系客服开通会员',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  _qrAsset,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 200,
                    height: 200,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2_rounded,
                            size: 48, color: Colors.black38),
                        SizedBox(height: 8),
                        Text(
                          '请联系客服开通会员',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.black54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('我知道了'),
            ),
          ],
        );
      },
    );
  }
}
