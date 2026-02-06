// lib/screens/about_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // این پکیج را در مرحله بعد اضافه می‌کنیم

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // آدرس کانال تلگرام شما
  // فعلاً آدرس اصلی تلگرام است، بعداً می‌توانید آن را با آدرس کانال خودتان جایگزین کنید
  final String _telegramChannelUrl = 'https://t.me/telegram';

  // تابعی برای باز کردن لینک
  Future<void> _launchUrl() async {
    final Uri url = Uri.parse(_telegramChannelUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      // اگر باز کردن لینک با خطا مواجه شد، می‌توانید یک پیام به کاربر نمایش دهید
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About US')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'iVPN',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'نسخه 1.0.0',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const Divider(height: 40),
            const Text(
              'اپلیکیشن iVPN یک ابزار امن و سریع برای دسترسی به اینترنت آزاد است. ما متعهد به حفظ حریم خصوصی و ارائه بهترین تجربه کاربری برای شما هستیم.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 24),

            // بخش لینک کانال تلگرام
            const Text(
              'پشتیبانی و سرورهای اختصاصی',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.send_outlined, color: Colors.blue),
              title: const Text('کانال تلگرام ما'),
              subtitle: const Text('برای خرید و دریافت سرورهای اختصاصی'),
              trailing: const Icon(Icons.open_in_new),
              onTap: _launchUrl, // با کلیک روی این آیتم، لینک باز می‌شود
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
