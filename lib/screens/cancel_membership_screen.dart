import 'package:flutter/material.dart';

class CancelMembershipPage extends StatefulWidget {
  const CancelMembershipPage({super.key});

  @override
  State<CancelMembershipPage> createState() => _CancelMembershipPageState();
}

class _CancelMembershipPageState extends State<CancelMembershipPage> {
  int? _selectedReasonIndex;
  final TextEditingController _otherReasonController = TextEditingController();

  final List<String> _reasons = [
    "Don't use it that much.",
    "Don't want to pay current amount.",
    "Other reasons"
  ];

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A0D17),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.orangeAccent),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Cancel Membership', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Text('😢', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 20),
            const Text(
              "We are sorry to see you go. What's the main reason for cancelling?",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            ...List.generate(_reasons.length, (index) {
              bool isSelected = _selectedReasonIndex == index;
              return GestureDetector(
                onTap: () => setState(() => _selectedReasonIndex = index),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.orangeAccent.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: isSelected ? Colors.orangeAccent : Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _reasons[index],
                          style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 16),
                        ),
                      ),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? Colors.orangeAccent : Colors.white30, width: 2),
                          color: isSelected ? Colors.orangeAccent : Colors.transparent,
                        ),
                        child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (_selectedReasonIndex == 2) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  controller: _otherReasonController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Please specify your reason in brief...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 60),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 55,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(30),
                        child: const Center(
                          child: Text('CANCEL', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 55,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E), 
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(30),
                        child: const Center(
                          child: Text("NO, DON'T CANCEL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
