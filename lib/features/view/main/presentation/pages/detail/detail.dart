import 'package:flutter/material.dart';

class DetailPage extends StatelessWidget {
  const DetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1113,
      height: 744,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(color: Color(0xFFF6F7F9)),
      child: Stack(
        children: [
          Positioned(
            left: 32,
            top: 32,
            child: SizedBox(
              width: 1049,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 16,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 16,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
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
                            spacing: 12,
                            children: [
                              SizedBox(
                                width: 681,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  spacing: 70,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      spacing: 12,
                                      children: [
                                        Container(
                                          width: 52,
                                          height: 52,
                                          padding: const EdgeInsets.all(16),
                                          decoration: ShapeDecoration(
                                            color: const Color(0xFFF6F7F9),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            spacing: 10,
                                            children: [
                                              Container(
                                                width: 24,
                                                height: 24,
                                                clipBehavior: Clip.antiAlias,
                                                decoration:
                                                    const BoxDecoration(),
                                                child: const Stack(),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Text(
                                          '16-stol',
                                          style: TextStyle(
                                            color: Color(0xFF2D2D2D),
                                            fontSize: 20,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      width: 480,
                                      padding: const EdgeInsets.all(14),
                                      clipBehavior: Clip.antiAlias,
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFFF6F7F9),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 10,
                                        children: [
                                          const Text(
                                            'Taom nomi bilan qidirish',
                                            style: TextStyle(
                                              color: Color(0xFF7B7B7B),
                                              fontSize: 16,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
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
                                width: 683,
                                clipBehavior: Clip.antiAlias,
                                decoration: const BoxDecoration(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  spacing: 8,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 16.50,
                                      ),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFF2D2D2D),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 10,
                                        children: [
                                          Text(
                                            'Barchasi',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 16.50,
                                      ),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFFF6F7F9),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 10,
                                        children: [
                                          Text(
                                            'Salatlar',
                                            style: TextStyle(
                                              color: Color(0xFF2D2D2D),
                                              fontSize: 16,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 16.50,
                                      ),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFFF6F7F9),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 10,
                                        children: [
                                          Text(
                                            'Birinchi taomlar',
                                            style: TextStyle(
                                              color: Color(0xFF2D2D2D),
                                              fontSize: 16,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 16.50,
                                      ),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFFF6F7F9),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 10,
                                        children: [
                                          Text(
                                            'Ikkinchi taomlar',
                                            style: TextStyle(
                                              color: Color(0xFF2D2D2D),
                                              fontSize: 16,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 16.50,
                                      ),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFFF6F7F9),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 10,
                                        children: [
                                          Text(
                                            'Ichimliklar',
                                            style: TextStyle(
                                              color: Color(0xFF2D2D2D),
                                              fontSize: 16,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 16.50,
                                      ),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFFF6F7F9),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 10,
                                        children: [
                                          Text(
                                            'Desertlar',
                                            style: TextStyle(
                                              color: Color(0xFF2D2D2D),
                                              fontSize: 16,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          height: 580,
                          padding: const EdgeInsets.all(16),
                          clipBehavior: Clip.antiAlias,
                          decoration: ShapeDecoration(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
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
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: 12,
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 12,
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF9747FF,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit:
                                                                    BoxFit.fill,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFFFF47FB,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Sho’rva',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit:
                                                                    BoxFit.fill,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFFFFC447,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 12,
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit:
                                                                    BoxFit.fill,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF19E29C,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit:
                                                                    BoxFit.fill,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFFE22020,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF4750FF,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 12,
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF9747FF,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF9747FF,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF9747FF,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 12,
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF9747FF,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF9747FF,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF9747FF,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 12,
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF9747FF,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF9747FF,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              clipBehavior: Clip.antiAlias,
                                              decoration: ShapeDecoration(
                                                color: const Color(0xFFF6F7F9),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 12,
                                                children: [
                                                  Container(
                                                    width: double.infinity,
                                                    height: 160,
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    decoration: ShapeDecoration(
                                                      color: Colors.white,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned(
                                                          left: 39,
                                                          top: 39,
                                                          child: Container(
                                                            width: 117,
                                                            height: 82,
                                                            decoration: const BoxDecoration(
                                                              image: DecorationImage(
                                                                image: NetworkImage(
                                                                  "https://placehold.co/117x82",
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left: 0,
                                                          top: 0,
                                                          child: Container(
                                                            width: 4,
                                                            height: 160,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF9747FF,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: 165,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      spacing: 8,
                                                      children: [
                                                        SizedBox(
                                                          width: 165,
                                                          child: Text(
                                                            'Gamburger',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.black,
                                                              fontSize: 20,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ),
                                                        Text(
                                                          '45 000 so’m',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFFB6633,
                                                            ) /* BrenD-FIled */,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 318,
                    height: 680,
                    padding: const EdgeInsets.only(
                      top: 10,
                      left: 16,
                      right: 16,
                      bottom: 16,
                    ),
                    clipBehavior: Clip.antiAlias,
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Stack(
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
                                'Buyurtmalar',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 20,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 13.50,
                                ),
                                decoration: ShapeDecoration(
                                  color: const Color(0x19DB1F1F),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  spacing: 10,
                                  children: [
                                    Text(
                                      'Tozalash',
                                      style: TextStyle(
                                        color: Color(0xFFDB2020),
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
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 12,
                            children: [
                              Container(
                                width: 286,
                                padding: const EdgeInsets.only(
                                  top: 7,
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                ),
                                decoration: ShapeDecoration(
                                  color: const Color(0xFFF6F7F9),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 16,
                                        children: [
                                          const Text(
                                            'Burger',
                                            style: TextStyle(
                                              color: Colors.black,
                                              fontSize: 20,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: const Color(0x1913AF1B),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              spacing: 10,
                                              children: [
                                                Text(
                                                  'Oshxonada',
                                                  style: TextStyle(
                                                    color: Color(0xFF13AF1B),
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Wrap(
                                        alignment: WrapAlignment.start,
                                        runAlignment: WrapAlignment.center,
                                        spacing: 7,
                                        runSpacing: 7,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              spacing: 10,
                                              children: [
                                                Text(
                                                  'Qo’shimcha achchiq',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              spacing: 10,
                                              children: [
                                                Text(
                                                  'Tuz kam',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Wrap(
                                              alignment: WrapAlignment.center,
                                              runAlignment:
                                                  WrapAlignment.center,
                                              spacing: 10,
                                              runSpacing: 10,
                                              children: [
                                                Text(
                                                  'Ketchup kamroq',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Wrap(
                                              alignment: WrapAlignment.center,
                                              runAlignment:
                                                  WrapAlignment.center,
                                              spacing: 10,
                                              runSpacing: 10,
                                              children: [
                                                Text(
                                                  'Sirsiz',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 262,
                                      child: Text(
                                        'Izoh: Mijoz qandaydir izoh aytsa qo’shib qo’yilgani shu yerda ko’rinadi',
                                        style: TextStyle(
                                          color: Color(0xFF7B7B7B),
                                          fontSize: 14,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 16,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            spacing: 16,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                decoration: ShapeDecoration(
                                                  color: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  spacing: 10,
                                                  children: [
                                                    Container(
                                                      width: 24,
                                                      height: 24,
                                                      clipBehavior:
                                                          Clip.antiAlias,
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: const Stack(),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Text(
                                                '3',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 20,
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                decoration: ShapeDecoration(
                                                  color: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  spacing: 10,
                                                  children: [
                                                    Container(
                                                      width: 24,
                                                      height: 24,
                                                      clipBehavior:
                                                          Clip.antiAlias,
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: const Stack(),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Text(
                                            '40 000 so’m',
                                            style: TextStyle(
                                              color: Colors.black,
                                              fontSize: 18,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 286,
                                padding: const EdgeInsets.only(
                                  top: 7,
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                ),
                                decoration: ShapeDecoration(
                                  color: const Color(0xFFF6F7F9),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 16,
                                        children: [
                                          const Text(
                                            'Burger',
                                            style: TextStyle(
                                              color: Colors.black,
                                              fontSize: 20,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: const Color(0x1913AF1B),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              spacing: 10,
                                              children: [
                                                Text(
                                                  'Oshxonada',
                                                  style: TextStyle(
                                                    color: Color(0xFF13AF1B),
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Wrap(
                                        alignment: WrapAlignment.start,
                                        runAlignment: WrapAlignment.center,
                                        spacing: 7,
                                        runSpacing: 7,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              spacing: 10,
                                              children: [
                                                Text(
                                                  'Qo’shimcha achchiq',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              spacing: 10,
                                              children: [
                                                Text(
                                                  'Tuz kam',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Wrap(
                                              alignment: WrapAlignment.center,
                                              runAlignment:
                                                  WrapAlignment.center,
                                              spacing: 10,
                                              runSpacing: 10,
                                              children: [
                                                Text(
                                                  'Ketchup kamroq',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Wrap(
                                              alignment: WrapAlignment.center,
                                              runAlignment:
                                                  WrapAlignment.center,
                                              spacing: 10,
                                              runSpacing: 10,
                                              children: [
                                                Text(
                                                  'Sirsiz',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 262,
                                      child: Text(
                                        'Izoh: Mijoz qandaydir izoh aytsa qo’shib qo’yilgani shu yerda ko’rinadi',
                                        style: TextStyle(
                                          color: Color(0xFF7B7B7B),
                                          fontSize: 14,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 16,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            spacing: 16,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                decoration: ShapeDecoration(
                                                  color: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  spacing: 10,
                                                  children: [
                                                    Container(
                                                      width: 24,
                                                      height: 24,
                                                      clipBehavior:
                                                          Clip.antiAlias,
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: const Stack(),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Text(
                                                '3',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 20,
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                decoration: ShapeDecoration(
                                                  color: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  spacing: 10,
                                                  children: [
                                                    Container(
                                                      width: 24,
                                                      height: 24,
                                                      clipBehavior:
                                                          Clip.antiAlias,
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: const Stack(),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Text(
                                            '40 000 so’m',
                                            style: TextStyle(
                                              color: Colors.black,
                                              fontSize: 18,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 286,
                                padding: const EdgeInsets.only(
                                  top: 7,
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                ),
                                decoration: ShapeDecoration(
                                  color: const Color(0xFFF6F7F9),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 16,
                                        children: [
                                          const Text(
                                            'Burger',
                                            style: TextStyle(
                                              color: Colors.black,
                                              fontSize: 20,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: const Color(0x1913AF1B),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              spacing: 10,
                                              children: [
                                                Text(
                                                  'Oshxonada',
                                                  style: TextStyle(
                                                    color: Color(0xFF13AF1B),
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Wrap(
                                        alignment: WrapAlignment.start,
                                        runAlignment: WrapAlignment.center,
                                        spacing: 7,
                                        runSpacing: 7,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              spacing: 10,
                                              children: [
                                                Text(
                                                  'Qo’shimcha achchiq',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              spacing: 10,
                                              children: [
                                                Text(
                                                  'Tuz kam',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Wrap(
                                              alignment: WrapAlignment.center,
                                              runAlignment:
                                                  WrapAlignment.center,
                                              spacing: 10,
                                              runSpacing: 10,
                                              children: [
                                                Text(
                                                  'Ketchup kamroq',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8.50,
                                            ),
                                            decoration: ShapeDecoration(
                                              color: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Wrap(
                                              alignment: WrapAlignment.center,
                                              runAlignment:
                                                  WrapAlignment.center,
                                              spacing: 10,
                                              runSpacing: 10,
                                              children: [
                                                Text(
                                                  'Sirsiz',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 262,
                                      child: Text(
                                        'Izoh: Mijoz qandaydir izoh aytsa qo’shib qo’yilgani shu yerda ko’rinadi',
                                        style: TextStyle(
                                          color: Color(0xFF7B7B7B),
                                          fontSize: 14,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        spacing: 16,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            spacing: 16,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                decoration: ShapeDecoration(
                                                  color: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  spacing: 10,
                                                  children: [
                                                    Container(
                                                      width: 24,
                                                      height: 24,
                                                      clipBehavior:
                                                          Clip.antiAlias,
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: const Stack(),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Text(
                                                '3',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 20,
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                decoration: ShapeDecoration(
                                                  color: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  spacing: 10,
                                                  children: [
                                                    Container(
                                                      width: 24,
                                                      height: 24,
                                                      clipBehavior:
                                                          Clip.antiAlias,
                                                      decoration:
                                                          const BoxDecoration(),
                                                      child: const Stack(),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Text(
                                            '40 000 so’m',
                                            style: TextStyle(
                                              color: Colors.black,
                                              fontSize: 18,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 493,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            clipBehavior: Clip.antiAlias,
                            decoration: const ShapeDecoration(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                side: BorderSide(
                                  width: 0.33,
                                  color: Color(0xFFC9C9C9),
                                ),
                              ),
                              shadows: [
                                BoxShadow(
                                  color: Color(0x11000000),
                                  blurRadius: 12,
                                  offset: Offset(0, -4),
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 16,
                              children: [
                                const SizedBox(
                                  width: 286,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    spacing: 57,
                                    children: [
                                      Text(
                                        'Jami:',
                                        style: TextStyle(
                                          color: Color(0xFF7B7B7B),
                                          fontSize: 16,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                      Text(
                                        '200 000 so’m',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 286,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    spacing: 8,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          width: 286,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 18.50,
                                          ),
                                          decoration: ShapeDecoration(
                                            color: const Color(0xFF2D2D2D),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            spacing: 10,
                                            children: [
                                              Text(
                                                'Oshxonaga yuborish',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 18.50,
                                        ),
                                        decoration: ShapeDecoration(
                                          color: const Color(
                                            0xFFFB6633,
                                          ) /* BrenD-FIled */,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          spacing: 10,
                                          children: [
                                            Text(
                                              'To’lovga o’tish',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontFamily: 'Inter',
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
