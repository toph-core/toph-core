import 'package:flutter/material.dart';

class SpecialReviewDialog extends StatelessWidget {
  const SpecialReviewDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
  width: 410,
  padding: const EdgeInsets.only(
    top: 10,
    left: 16,
    right: 16,
    bottom: 16,
  ),
  decoration: ShapeDecoration(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    ),
  ),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.start,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 16,
    children: [
      SizedBox(
        width: double.infinity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 16,
          children: [
            const Text(
              'Maxsus izoh',
              style: TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(10),
              decoration: ShapeDecoration(
                color: const Color(0xFFF6F7F9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(40),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: 10,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(),
                    child: const Stack(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      Container(
        width: double.infinity,
        height: 116,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16.50),
        decoration: ShapeDecoration(
          color: const Color(0xFFF6F7F9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(
              'Izoh uchun',
              style: TextStyle(
                color: Color(0xFF7B7B7B),
                fontSize: 16,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    ],
  ),
);}}