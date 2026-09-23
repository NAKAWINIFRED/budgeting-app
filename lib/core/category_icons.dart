import 'package:flutter/material.dart';

/// Maps the iconKey stored in the database to an actual icon.
const Map<String, IconData> _icons = {
  'home': Icons.home_rounded,
  'shopping_cart': Icons.shopping_cart_rounded,
  'cleaning_services': Icons.cleaning_services_rounded,
  'directions_bus': Icons.directions_bus_rounded,
  'bolt': Icons.bolt_rounded,
  'phone_android': Icons.phone_android_rounded,
  'medical_services': Icons.medical_services_rounded,
  'school': Icons.school_rounded,
  'family_restroom': Icons.family_restroom_rounded,
  'restaurant': Icons.restaurant_rounded,
  'movie': Icons.movie_rounded,
  'shopping_bag': Icons.shopping_bag_rounded,
  'spa': Icons.spa_rounded,
  'card_giftcard': Icons.card_giftcard_rounded,
  'more_horiz': Icons.more_horiz_rounded,
  'work': Icons.work_rounded,
  'storefront': Icons.storefront_rounded,
  'handyman': Icons.handyman_rounded,
  'redeem': Icons.redeem_rounded,
  'savings': Icons.savings_rounded,
  'shield': Icons.shield_rounded,
  'directions_car': Icons.directions_car_rounded,
  'flight': Icons.flight_rounded,
  'phone_iphone': Icons.phone_iphone_rounded,
  'celebration': Icons.celebration_rounded,
  'beach_access': Icons.beach_access_rounded,
  'favorite': Icons.favorite_rounded,
  'trending_up': Icons.trending_up_rounded,
  'payments': Icons.payments_rounded,
};

IconData iconFor(String? key) => _icons[key] ?? Icons.more_horiz_rounded;
