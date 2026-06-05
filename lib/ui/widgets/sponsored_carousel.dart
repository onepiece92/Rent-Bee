import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import 'glass.dart';
import 'toast.dart';

/// One partner entry in a [SponsoredCarousel].
class Sponsor {
  final String name;
  final String tagline;
  final String url;
  final IconData icon;
  const Sponsor({
    required this.name,
    required this.tagline,
    required this.url,
    this.icon = Icons.campaign_rounded,
  });
}

/// Default partners shown when no [SponsoredCarousel.sponsors] are supplied.
const kDefaultSponsors = <Sponsor>[
  Sponsor(
    name: 'Brand Builder Pvt Ltd',
    tagline: 'Branding & marketing',
    url: 'https://vcardly.link/brandbuilder',
    icon: Icons.brush_rounded,
  ),
  Sponsor(
    name: 'Rebuzz POS',
    tagline: 'Point of sale system',
    url: 'https://vcardly.link/v/o/Qk7NXOSn',
    icon: Icons.point_of_sale_rounded,
  ),
  Sponsor(
    name: 'Expense Tracker',
    tagline: 'Track your expenses',
    url: 'https://vcardly.link/v/o/openexpense-exVmWLAL',
    icon: Icons.account_balance_wallet_rounded,
  ),
];

/// A compact, auto-advancing "Sponsored" carousel of partner links. Swipeable,
/// with page-dot indicators; tapping a card opens its link in the browser.
/// Self-contained and reusable anywhere (home, reports, …).
class SponsoredCarousel extends StatefulWidget {
  final List<Sponsor> sponsors;
  final Duration interval;
  const SponsoredCarousel({
    super.key,
    this.sponsors = kDefaultSponsors,
    this.interval = const Duration(seconds: 4),
  });

  @override
  State<SponsoredCarousel> createState() => _SponsoredCarouselState();
}

class _SponsoredCarouselState extends State<SponsoredCarousel> {
  final _controller = PageController(viewportFraction: 0.9);
  Timer? _timer;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    if (widget.sponsors.length > 1) {
      _timer = Timer.periodic(widget.interval, (_) => _advance());
    }
  }

  void _advance() {
    if (!mounted || !_controller.hasClients) return;
    final next = (_current + 1) % widget.sponsors.length;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      showToast(context, 'Could not open the link', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sponsors = widget.sponsors;
    if (sponsors.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'SPONSORED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: Brand.muted,
              ),
            ),
          ),
          SizedBox(
            height: 78,
            child: PageView.builder(
              controller: _controller,
              itemCount: sponsors.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _SponsorCard(
                  sponsor: sponsors[i],
                  onTap: () => _open(sponsors[i].url),
                ),
              ),
            ),
          ),
          if (sponsors.length > 1) ...[
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < sponsors.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _current ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _current ? Brand.orange : Brand.glassBorder,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SponsorCard extends StatelessWidget {
  final Sponsor sponsor;
  final VoidCallback onTap;
  const _SponsorCard({required this.sponsor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: Brand.orangeGradient,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(sponsor.icon, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sponsor.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  sponsor.tagline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Brand.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.open_in_new_rounded,
              size: 16, color: Brand.orangeSoft),
        ],
      ),
    );
  }
}
