import 'package:flutter/material.dart';

class ListingPhotoCarousel extends StatefulWidget {
  const ListingPhotoCarousel({
    super.key,
    required this.imageUrls,
    this.height = 250,
  });

  final List<String> imageUrls;
  final double height;

  @override
  State<ListingPhotoCarousel> createState() => _ListingPhotoCarouselState();
}

class _ListingPhotoCarouselState extends State<ListingPhotoCarousel> {
  late final PageController _controller;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: SizedBox(
          height: widget.height,
          child: widget.imageUrls.isEmpty
              ? _placeholder()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _controller,
                      itemCount: widget.imageUrls.length,
                      onPageChanged: (page) =>
                          setState(() => _currentPage = page),
                      itemBuilder: (context, index) => Image.network(
                        widget.imageUrls[index],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => _placeholder(),
                      ),
                    ),
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children:
                            List.generate(widget.imageUrls.length, (index) {
                          final selected = index == _currentPage;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: selected ? 17 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
        ),
      );

  Widget _placeholder() => Container(
        color: const Color(0xFFDCE9E0),
        alignment: Alignment.center,
        child: const Icon(Icons.apartment_rounded,
            size: 58, color: Color(0xFF709581)),
      );
}
