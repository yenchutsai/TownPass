import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/page/city_service/widget/official_service_card/official_service_card_widget.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_widget.dart';
import 'package:town_pass/page/city_service/widget/trending_service_widget.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/util/tp_text.dart';

class CityServiceView extends StatelessWidget {
  const CityServiceView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TPColors.white,
      appBar: TPAppBar(
        showLogo: true,
        title: '服務',
        leading: IconButton(
          icon: Semantics(
            label: '帳戶',
            child: Assets.svg.iconPerson.svg(),
          ),
          onPressed: () => Get.toNamed(TPRoute.account),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _searchBar(),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _myServiceTitle(),
          ),
          PinnedServiceWidget(
            onMoreTap: () => Get.toNamed(TPRoute.serviceEdit),
          ),
          const SizedBox(height: 50),
          const OfficialServiceCardWidget(),
          const SizedBox(height: 20),
          const TrendingServiceWidget(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// 搜尋入口：點了以後進入搜尋頁。
  Widget _searchBar() {
    return Semantics(
      button: true,
      label: '搜尋服務，可以用您的語言輸入',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Get.toNamed(TPRoute.serviceSearch),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: TPColors.grayscale50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.search, color: TPColors.grayscale500),
              SizedBox(width: 8),
              Expanded(
                child: TPText(
                  '您想辦什麼事？ Search / Cari / Tìm / ค้นหา',
                  style: TPTextStyles.bodyRegular,
                  color: TPColors.grayscale500,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _myServiceTitle() {
    return Semantics(
      explicitChildNodes: true,
      child: Row(
        children: [
          TPText(
            '我的服務',
            style: TPTextStyles.h3SemiBold.copyWith(fontSize: 18),
            color: TPColors.grayscale900,
          ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Get.toNamed(TPRoute.serviceEdit),
            child: Row(
              children: [
                const TPText(
                  '更多',
                  style: TPTextStyles.h3Regular,
                  color: TPColors.grayscale700,
                ),
                const SizedBox(width: 8.0),
                Assets.svg.iconExpand.svg(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
