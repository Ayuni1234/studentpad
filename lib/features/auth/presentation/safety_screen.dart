import 'package:flutter/material.dart';

const _safetyForest = Color(0xFF134E3F);
const _safetySage = Color(0xFFE8F0EC);
const _safetyCanvas = Color(0xFFF9FBF9);

class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _safetyCanvas,
        appBar: AppBar(
          backgroundColor: _safetyCanvas,
          title: const Text('Safety & privacy',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _safetyForest,
                borderRadius: BorderRadius.circular(23),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: Colors.white, size: 30),
                  SizedBox(height: 12),
                  Text('Make room for a safer move.',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text(
                    'StudentPad helps you meet verified students. Take time to confirm the room and rental details before making decisions.',
                    style: TextStyle(color: Colors.white, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SafetySection(
              icon: Icons.school_outlined,
              title: 'Student verification',
              children: const [
                'A student ID image is submitted for review. Uploading it does not instantly verify your account.',
                'The ID image is kept in private storage for the verification workflow. It is not part of your public profile or listing.',
                'Verified status unlocks student listings, roommate matches, and peer chats.',
              ],
            ),
            _SafetySection(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Before you meet or pay',
              children: const [
                'Keep early conversations in StudentPad while you learn about the person and the housing arrangement.',
                'Arrange an in-person or live video viewing. Confirm the address, who is renting the property, what is included, and the written terms.',
                'Do not send a deposit or rent until you have independently checked the property and the person’s authority to rent it.',
                'If you meet in person, choose a public place first and tell someone you trust where you are going.',
              ],
            ),
            _SafetySection(
              icon: Icons.tune_rounded,
              title: 'Use matches as a starting point',
              children: const [
                'Compatibility reflects the university, budget range, cleanliness preference, and sleep schedule you provide.',
                'A score can help start a conversation, but it cannot guarantee that you will get along. Talk through expectations like chores, guests, noise, and bills.',
              ],
            ),
            _SafetySection(
              icon: Icons.lock_outline_rounded,
              title: 'Protect your information',
              children: const [
                'Share only the personal details needed to evaluate a potential roommate or room.',
                'Never send passwords, sign-in codes, or payment details in chat.',
                'Use a strong password for your account and sign out on a device other people use.',
              ],
            ),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: _safetySage,
                borderRadius: BorderRadius.circular(17),
              ),
              child: const Text(
                'If something feels rushed or inconsistent, pause the conversation and verify the details before moving forward.',
                style: TextStyle(
                    color: _safetyForest,
                    fontWeight: FontWeight.w700,
                    height: 1.4),
              ),
            ),
          ],
        ),
      );
}

class _SafetySection extends StatelessWidget {
  const _SafetySection({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<String> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 11),
        decoration: BoxDecoration(
          color: _safetySage,
          borderRadius: BorderRadius.circular(19),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D173D30), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: _safetyForest, size: 21),
            const SizedBox(width: 9),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: _safetyForest,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          ...children.map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 7),
                      child: Icon(Icons.circle, size: 5, color: _safetyForest),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(tip,
                          style: const TextStyle(
                              color: Color(0xFF56645C), height: 1.4)),
                    ),
                  ],
                ),
              )),
        ]),
      );
}
