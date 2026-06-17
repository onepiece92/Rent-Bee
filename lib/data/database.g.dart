// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $UnitsTable extends Units with TableInfo<$UnitsTable, Unit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UnitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _cloudIdMeta = const VerificationMeta(
    'cloudId',
  );
  @override
  late final GeneratedColumn<String> cloudId = GeneratedColumn<String>(
    'cloud_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 32,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _tenantNameMeta = const VerificationMeta(
    'tenantName',
  );
  @override
  late final GeneratedColumn<String> tenantName = GeneratedColumn<String>(
    'tenant_name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 120,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessTypeMeta = const VerificationMeta(
    'businessType',
  );
  @override
  late final GeneratedColumn<String> businessType = GeneratedColumn<String>(
    'business_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _monthlyRentMeta = const VerificationMeta(
    'monthlyRent',
  );
  @override
  late final GeneratedColumn<int> monthlyRent = GeneratedColumn<int>(
    'monthly_rent',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _startedOnMeta = const VerificationMeta(
    'startedOn',
  );
  @override
  late final GeneratedColumn<DateTime> startedOn = GeneratedColumn<DateTime>(
    'started_on',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastRaisedOnMeta = const VerificationMeta(
    'lastRaisedOn',
  );
  @override
  late final GeneratedColumn<DateTime> lastRaisedOn = GeneratedColumn<DateTime>(
    'last_raised_on',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _depositAmountMeta = const VerificationMeta(
    'depositAmount',
  );
  @override
  late final GeneratedColumn<int> depositAmount = GeneratedColumn<int>(
    'deposit_amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _depositRefundedMeta = const VerificationMeta(
    'depositRefunded',
  );
  @override
  late final GeneratedColumn<bool> depositRefunded = GeneratedColumn<bool>(
    'deposit_refunded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deposit_refunded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _depositRefundedOnMeta = const VerificationMeta(
    'depositRefundedOn',
  );
  @override
  late final GeneratedColumn<DateTime> depositRefundedOn =
      GeneratedColumn<DateTime>(
        'deposit_refunded_on',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cloudId,
    code,
    tenantName,
    businessType,
    monthlyRent,
    phone,
    notes,
    isActive,
    createdAt,
    startedOn,
    lastRaisedOn,
    depositAmount,
    depositRefunded,
    depositRefundedOn,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'units';
  @override
  VerificationContext validateIntegrity(
    Insertable<Unit> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cloud_id')) {
      context.handle(
        _cloudIdMeta,
        cloudId.isAcceptableOrUnknown(data['cloud_id']!, _cloudIdMeta),
      );
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('tenant_name')) {
      context.handle(
        _tenantNameMeta,
        tenantName.isAcceptableOrUnknown(data['tenant_name']!, _tenantNameMeta),
      );
    } else if (isInserting) {
      context.missing(_tenantNameMeta);
    }
    if (data.containsKey('business_type')) {
      context.handle(
        _businessTypeMeta,
        businessType.isAcceptableOrUnknown(
          data['business_type']!,
          _businessTypeMeta,
        ),
      );
    }
    if (data.containsKey('monthly_rent')) {
      context.handle(
        _monthlyRentMeta,
        monthlyRent.isAcceptableOrUnknown(
          data['monthly_rent']!,
          _monthlyRentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_monthlyRentMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('started_on')) {
      context.handle(
        _startedOnMeta,
        startedOn.isAcceptableOrUnknown(data['started_on']!, _startedOnMeta),
      );
    }
    if (data.containsKey('last_raised_on')) {
      context.handle(
        _lastRaisedOnMeta,
        lastRaisedOn.isAcceptableOrUnknown(
          data['last_raised_on']!,
          _lastRaisedOnMeta,
        ),
      );
    }
    if (data.containsKey('deposit_amount')) {
      context.handle(
        _depositAmountMeta,
        depositAmount.isAcceptableOrUnknown(
          data['deposit_amount']!,
          _depositAmountMeta,
        ),
      );
    }
    if (data.containsKey('deposit_refunded')) {
      context.handle(
        _depositRefundedMeta,
        depositRefunded.isAcceptableOrUnknown(
          data['deposit_refunded']!,
          _depositRefundedMeta,
        ),
      );
    }
    if (data.containsKey('deposit_refunded_on')) {
      context.handle(
        _depositRefundedOnMeta,
        depositRefundedOn.isAcceptableOrUnknown(
          data['deposit_refunded_on']!,
          _depositRefundedOnMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Unit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Unit(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cloudId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_id'],
      ),
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      tenantName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_name'],
      )!,
      businessType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_type'],
      )!,
      monthlyRent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}monthly_rent'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      startedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_on'],
      ),
      lastRaisedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_raised_on'],
      ),
      depositAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deposit_amount'],
      )!,
      depositRefunded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deposit_refunded'],
      )!,
      depositRefundedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deposit_refunded_on'],
      ),
    );
  }

  @override
  $UnitsTable createAlias(String alias) {
    return $UnitsTable(attachedDatabase, alias);
  }
}

class Unit extends DataClass implements Insertable<Unit> {
  final int id;

  /// Stable cross-device identity for cloud sync (a UUID). The local [id]
  /// differs per device and [code] is user-editable, so neither can key the
  /// Firestore document — this can. Nullable only for the brief window of the
  /// v4 migration backfill; every row created afterwards has one. Uniqueness is
  /// enforced by a unique index (see [beforeOpen]) rather than an inline
  /// UNIQUE, because SQLite's `ALTER TABLE ADD COLUMN` cannot add a UNIQUE
  /// column.
  final String? cloudId;
  final String code;
  final String tenantName;
  final String businessType;
  final int monthlyRent;
  final String? phone;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;

  /// When the tenant joined / the current rent started. Anchors the annual
  /// lease escalation: a unit is only raised once a full year has passed since
  /// this date (so a newly-joined tenant isn't raised immediately). Nullable
  /// for legacy units with no recorded start.
  final DateTime? startedOn;

  /// Last time the annual lease escalation was applied to this unit. Makes the raise
  /// idempotent within a year — eligibility is measured from
  /// `lastRaisedOn ?? startedOn`. Null until the first raise.
  final DateTime? lastRaisedOn;

  /// Refundable security deposit held for the tenant, whole NPR. 0 = none.
  final int depositAmount;

  /// Whether the deposit has been returned to the tenant. false = still held.
  final bool depositRefunded;

  /// When the deposit was refunded. Null while still held.
  final DateTime? depositRefundedOn;
  const Unit({
    required this.id,
    this.cloudId,
    required this.code,
    required this.tenantName,
    required this.businessType,
    required this.monthlyRent,
    this.phone,
    this.notes,
    required this.isActive,
    required this.createdAt,
    this.startedOn,
    this.lastRaisedOn,
    required this.depositAmount,
    required this.depositRefunded,
    this.depositRefundedOn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || cloudId != null) {
      map['cloud_id'] = Variable<String>(cloudId);
    }
    map['code'] = Variable<String>(code);
    map['tenant_name'] = Variable<String>(tenantName);
    map['business_type'] = Variable<String>(businessType);
    map['monthly_rent'] = Variable<int>(monthlyRent);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || startedOn != null) {
      map['started_on'] = Variable<DateTime>(startedOn);
    }
    if (!nullToAbsent || lastRaisedOn != null) {
      map['last_raised_on'] = Variable<DateTime>(lastRaisedOn);
    }
    map['deposit_amount'] = Variable<int>(depositAmount);
    map['deposit_refunded'] = Variable<bool>(depositRefunded);
    if (!nullToAbsent || depositRefundedOn != null) {
      map['deposit_refunded_on'] = Variable<DateTime>(depositRefundedOn);
    }
    return map;
  }

  UnitsCompanion toCompanion(bool nullToAbsent) {
    return UnitsCompanion(
      id: Value(id),
      cloudId: cloudId == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudId),
      code: Value(code),
      tenantName: Value(tenantName),
      businessType: Value(businessType),
      monthlyRent: Value(monthlyRent),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      startedOn: startedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(startedOn),
      lastRaisedOn: lastRaisedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRaisedOn),
      depositAmount: Value(depositAmount),
      depositRefunded: Value(depositRefunded),
      depositRefundedOn: depositRefundedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(depositRefundedOn),
    );
  }

  factory Unit.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Unit(
      id: serializer.fromJson<int>(json['id']),
      cloudId: serializer.fromJson<String?>(json['cloudId']),
      code: serializer.fromJson<String>(json['code']),
      tenantName: serializer.fromJson<String>(json['tenantName']),
      businessType: serializer.fromJson<String>(json['businessType']),
      monthlyRent: serializer.fromJson<int>(json['monthlyRent']),
      phone: serializer.fromJson<String?>(json['phone']),
      notes: serializer.fromJson<String?>(json['notes']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      startedOn: serializer.fromJson<DateTime?>(json['startedOn']),
      lastRaisedOn: serializer.fromJson<DateTime?>(json['lastRaisedOn']),
      depositAmount: serializer.fromJson<int>(json['depositAmount']),
      depositRefunded: serializer.fromJson<bool>(json['depositRefunded']),
      depositRefundedOn: serializer.fromJson<DateTime?>(
        json['depositRefundedOn'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cloudId': serializer.toJson<String?>(cloudId),
      'code': serializer.toJson<String>(code),
      'tenantName': serializer.toJson<String>(tenantName),
      'businessType': serializer.toJson<String>(businessType),
      'monthlyRent': serializer.toJson<int>(monthlyRent),
      'phone': serializer.toJson<String?>(phone),
      'notes': serializer.toJson<String?>(notes),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'startedOn': serializer.toJson<DateTime?>(startedOn),
      'lastRaisedOn': serializer.toJson<DateTime?>(lastRaisedOn),
      'depositAmount': serializer.toJson<int>(depositAmount),
      'depositRefunded': serializer.toJson<bool>(depositRefunded),
      'depositRefundedOn': serializer.toJson<DateTime?>(depositRefundedOn),
    };
  }

  Unit copyWith({
    int? id,
    Value<String?> cloudId = const Value.absent(),
    String? code,
    String? tenantName,
    String? businessType,
    int? monthlyRent,
    Value<String?> phone = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
    Value<DateTime?> startedOn = const Value.absent(),
    Value<DateTime?> lastRaisedOn = const Value.absent(),
    int? depositAmount,
    bool? depositRefunded,
    Value<DateTime?> depositRefundedOn = const Value.absent(),
  }) => Unit(
    id: id ?? this.id,
    cloudId: cloudId.present ? cloudId.value : this.cloudId,
    code: code ?? this.code,
    tenantName: tenantName ?? this.tenantName,
    businessType: businessType ?? this.businessType,
    monthlyRent: monthlyRent ?? this.monthlyRent,
    phone: phone.present ? phone.value : this.phone,
    notes: notes.present ? notes.value : this.notes,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    startedOn: startedOn.present ? startedOn.value : this.startedOn,
    lastRaisedOn: lastRaisedOn.present ? lastRaisedOn.value : this.lastRaisedOn,
    depositAmount: depositAmount ?? this.depositAmount,
    depositRefunded: depositRefunded ?? this.depositRefunded,
    depositRefundedOn: depositRefundedOn.present
        ? depositRefundedOn.value
        : this.depositRefundedOn,
  );
  Unit copyWithCompanion(UnitsCompanion data) {
    return Unit(
      id: data.id.present ? data.id.value : this.id,
      cloudId: data.cloudId.present ? data.cloudId.value : this.cloudId,
      code: data.code.present ? data.code.value : this.code,
      tenantName: data.tenantName.present
          ? data.tenantName.value
          : this.tenantName,
      businessType: data.businessType.present
          ? data.businessType.value
          : this.businessType,
      monthlyRent: data.monthlyRent.present
          ? data.monthlyRent.value
          : this.monthlyRent,
      phone: data.phone.present ? data.phone.value : this.phone,
      notes: data.notes.present ? data.notes.value : this.notes,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      startedOn: data.startedOn.present ? data.startedOn.value : this.startedOn,
      lastRaisedOn: data.lastRaisedOn.present
          ? data.lastRaisedOn.value
          : this.lastRaisedOn,
      depositAmount: data.depositAmount.present
          ? data.depositAmount.value
          : this.depositAmount,
      depositRefunded: data.depositRefunded.present
          ? data.depositRefunded.value
          : this.depositRefunded,
      depositRefundedOn: data.depositRefundedOn.present
          ? data.depositRefundedOn.value
          : this.depositRefundedOn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Unit(')
          ..write('id: $id, ')
          ..write('cloudId: $cloudId, ')
          ..write('code: $code, ')
          ..write('tenantName: $tenantName, ')
          ..write('businessType: $businessType, ')
          ..write('monthlyRent: $monthlyRent, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('startedOn: $startedOn, ')
          ..write('lastRaisedOn: $lastRaisedOn, ')
          ..write('depositAmount: $depositAmount, ')
          ..write('depositRefunded: $depositRefunded, ')
          ..write('depositRefundedOn: $depositRefundedOn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cloudId,
    code,
    tenantName,
    businessType,
    monthlyRent,
    phone,
    notes,
    isActive,
    createdAt,
    startedOn,
    lastRaisedOn,
    depositAmount,
    depositRefunded,
    depositRefundedOn,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Unit &&
          other.id == this.id &&
          other.cloudId == this.cloudId &&
          other.code == this.code &&
          other.tenantName == this.tenantName &&
          other.businessType == this.businessType &&
          other.monthlyRent == this.monthlyRent &&
          other.phone == this.phone &&
          other.notes == this.notes &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.startedOn == this.startedOn &&
          other.lastRaisedOn == this.lastRaisedOn &&
          other.depositAmount == this.depositAmount &&
          other.depositRefunded == this.depositRefunded &&
          other.depositRefundedOn == this.depositRefundedOn);
}

class UnitsCompanion extends UpdateCompanion<Unit> {
  final Value<int> id;
  final Value<String?> cloudId;
  final Value<String> code;
  final Value<String> tenantName;
  final Value<String> businessType;
  final Value<int> monthlyRent;
  final Value<String?> phone;
  final Value<String?> notes;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime?> startedOn;
  final Value<DateTime?> lastRaisedOn;
  final Value<int> depositAmount;
  final Value<bool> depositRefunded;
  final Value<DateTime?> depositRefundedOn;
  const UnitsCompanion({
    this.id = const Value.absent(),
    this.cloudId = const Value.absent(),
    this.code = const Value.absent(),
    this.tenantName = const Value.absent(),
    this.businessType = const Value.absent(),
    this.monthlyRent = const Value.absent(),
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.startedOn = const Value.absent(),
    this.lastRaisedOn = const Value.absent(),
    this.depositAmount = const Value.absent(),
    this.depositRefunded = const Value.absent(),
    this.depositRefundedOn = const Value.absent(),
  });
  UnitsCompanion.insert({
    this.id = const Value.absent(),
    this.cloudId = const Value.absent(),
    required String code,
    required String tenantName,
    this.businessType = const Value.absent(),
    required int monthlyRent,
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.startedOn = const Value.absent(),
    this.lastRaisedOn = const Value.absent(),
    this.depositAmount = const Value.absent(),
    this.depositRefunded = const Value.absent(),
    this.depositRefundedOn = const Value.absent(),
  }) : code = Value(code),
       tenantName = Value(tenantName),
       monthlyRent = Value(monthlyRent);
  static Insertable<Unit> custom({
    Expression<int>? id,
    Expression<String>? cloudId,
    Expression<String>? code,
    Expression<String>? tenantName,
    Expression<String>? businessType,
    Expression<int>? monthlyRent,
    Expression<String>? phone,
    Expression<String>? notes,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? startedOn,
    Expression<DateTime>? lastRaisedOn,
    Expression<int>? depositAmount,
    Expression<bool>? depositRefunded,
    Expression<DateTime>? depositRefundedOn,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cloudId != null) 'cloud_id': cloudId,
      if (code != null) 'code': code,
      if (tenantName != null) 'tenant_name': tenantName,
      if (businessType != null) 'business_type': businessType,
      if (monthlyRent != null) 'monthly_rent': monthlyRent,
      if (phone != null) 'phone': phone,
      if (notes != null) 'notes': notes,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (startedOn != null) 'started_on': startedOn,
      if (lastRaisedOn != null) 'last_raised_on': lastRaisedOn,
      if (depositAmount != null) 'deposit_amount': depositAmount,
      if (depositRefunded != null) 'deposit_refunded': depositRefunded,
      if (depositRefundedOn != null) 'deposit_refunded_on': depositRefundedOn,
    });
  }

  UnitsCompanion copyWith({
    Value<int>? id,
    Value<String?>? cloudId,
    Value<String>? code,
    Value<String>? tenantName,
    Value<String>? businessType,
    Value<int>? monthlyRent,
    Value<String?>? phone,
    Value<String?>? notes,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime?>? startedOn,
    Value<DateTime?>? lastRaisedOn,
    Value<int>? depositAmount,
    Value<bool>? depositRefunded,
    Value<DateTime?>? depositRefundedOn,
  }) {
    return UnitsCompanion(
      id: id ?? this.id,
      cloudId: cloudId ?? this.cloudId,
      code: code ?? this.code,
      tenantName: tenantName ?? this.tenantName,
      businessType: businessType ?? this.businessType,
      monthlyRent: monthlyRent ?? this.monthlyRent,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      startedOn: startedOn ?? this.startedOn,
      lastRaisedOn: lastRaisedOn ?? this.lastRaisedOn,
      depositAmount: depositAmount ?? this.depositAmount,
      depositRefunded: depositRefunded ?? this.depositRefunded,
      depositRefundedOn: depositRefundedOn ?? this.depositRefundedOn,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cloudId.present) {
      map['cloud_id'] = Variable<String>(cloudId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (tenantName.present) {
      map['tenant_name'] = Variable<String>(tenantName.value);
    }
    if (businessType.present) {
      map['business_type'] = Variable<String>(businessType.value);
    }
    if (monthlyRent.present) {
      map['monthly_rent'] = Variable<int>(monthlyRent.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (startedOn.present) {
      map['started_on'] = Variable<DateTime>(startedOn.value);
    }
    if (lastRaisedOn.present) {
      map['last_raised_on'] = Variable<DateTime>(lastRaisedOn.value);
    }
    if (depositAmount.present) {
      map['deposit_amount'] = Variable<int>(depositAmount.value);
    }
    if (depositRefunded.present) {
      map['deposit_refunded'] = Variable<bool>(depositRefunded.value);
    }
    if (depositRefundedOn.present) {
      map['deposit_refunded_on'] = Variable<DateTime>(depositRefundedOn.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UnitsCompanion(')
          ..write('id: $id, ')
          ..write('cloudId: $cloudId, ')
          ..write('code: $code, ')
          ..write('tenantName: $tenantName, ')
          ..write('businessType: $businessType, ')
          ..write('monthlyRent: $monthlyRent, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('startedOn: $startedOn, ')
          ..write('lastRaisedOn: $lastRaisedOn, ')
          ..write('depositAmount: $depositAmount, ')
          ..write('depositRefunded: $depositRefunded, ')
          ..write('depositRefundedOn: $depositRefundedOn')
          ..write(')'))
        .toString();
  }
}

class $PaymentsTable extends Payments with TableInfo<$PaymentsTable, Payment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _unitIdMeta = const VerificationMeta('unitId');
  @override
  late final GeneratedColumn<int> unitId = GeneratedColumn<int>(
    'unit_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES units (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _monthMeta = const VerificationMeta('month');
  @override
  late final GeneratedColumn<int> month = GeneratedColumn<int>(
    'month',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paidOnMeta = const VerificationMeta('paidOn');
  @override
  late final GeneratedColumn<DateTime> paidOn = GeneratedColumn<DateTime>(
    'paid_on',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PayMethod, String> method =
      GeneratedColumn<String>(
        'method',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(PayMethod.cash.name),
      ).withConverter<PayMethod>($PaymentsTable.$convertermethod);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    unitId,
    year,
    month,
    amount,
    paidOn,
    method,
    note,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Payment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('unit_id')) {
      context.handle(
        _unitIdMeta,
        unitId.isAcceptableOrUnknown(data['unit_id']!, _unitIdMeta),
      );
    } else if (isInserting) {
      context.missing(_unitIdMeta);
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    } else if (isInserting) {
      context.missing(_yearMeta);
    }
    if (data.containsKey('month')) {
      context.handle(
        _monthMeta,
        month.isAcceptableOrUnknown(data['month']!, _monthMeta),
      );
    } else if (isInserting) {
      context.missing(_monthMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('paid_on')) {
      context.handle(
        _paidOnMeta,
        paidOn.isAcceptableOrUnknown(data['paid_on']!, _paidOnMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {unitId, year, month},
  ];
  @override
  Payment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Payment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      unitId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_id'],
      )!,
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      )!,
      month: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}month'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      paidOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paid_on'],
      ),
      method: $PaymentsTable.$convertermethod.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}method'],
        )!,
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PaymentsTable createAlias(String alias) {
    return $PaymentsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PayMethod, String, String> $convertermethod =
      const EnumNameConverter<PayMethod>(PayMethod.values);
}

class Payment extends DataClass implements Insertable<Payment> {
  final int id;
  final int unitId;
  final int year;
  final int month;
  final int amount;
  final DateTime? paidOn;
  final PayMethod method;
  final String? note;
  final DateTime createdAt;
  const Payment({
    required this.id,
    required this.unitId,
    required this.year,
    required this.month,
    required this.amount,
    this.paidOn,
    required this.method,
    this.note,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['unit_id'] = Variable<int>(unitId);
    map['year'] = Variable<int>(year);
    map['month'] = Variable<int>(month);
    map['amount'] = Variable<int>(amount);
    if (!nullToAbsent || paidOn != null) {
      map['paid_on'] = Variable<DateTime>(paidOn);
    }
    {
      map['method'] = Variable<String>(
        $PaymentsTable.$convertermethod.toSql(method),
      );
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PaymentsCompanion toCompanion(bool nullToAbsent) {
    return PaymentsCompanion(
      id: Value(id),
      unitId: Value(unitId),
      year: Value(year),
      month: Value(month),
      amount: Value(amount),
      paidOn: paidOn == null && nullToAbsent
          ? const Value.absent()
          : Value(paidOn),
      method: Value(method),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
    );
  }

  factory Payment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Payment(
      id: serializer.fromJson<int>(json['id']),
      unitId: serializer.fromJson<int>(json['unitId']),
      year: serializer.fromJson<int>(json['year']),
      month: serializer.fromJson<int>(json['month']),
      amount: serializer.fromJson<int>(json['amount']),
      paidOn: serializer.fromJson<DateTime?>(json['paidOn']),
      method: $PaymentsTable.$convertermethod.fromJson(
        serializer.fromJson<String>(json['method']),
      ),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'unitId': serializer.toJson<int>(unitId),
      'year': serializer.toJson<int>(year),
      'month': serializer.toJson<int>(month),
      'amount': serializer.toJson<int>(amount),
      'paidOn': serializer.toJson<DateTime?>(paidOn),
      'method': serializer.toJson<String>(
        $PaymentsTable.$convertermethod.toJson(method),
      ),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Payment copyWith({
    int? id,
    int? unitId,
    int? year,
    int? month,
    int? amount,
    Value<DateTime?> paidOn = const Value.absent(),
    PayMethod? method,
    Value<String?> note = const Value.absent(),
    DateTime? createdAt,
  }) => Payment(
    id: id ?? this.id,
    unitId: unitId ?? this.unitId,
    year: year ?? this.year,
    month: month ?? this.month,
    amount: amount ?? this.amount,
    paidOn: paidOn.present ? paidOn.value : this.paidOn,
    method: method ?? this.method,
    note: note.present ? note.value : this.note,
    createdAt: createdAt ?? this.createdAt,
  );
  Payment copyWithCompanion(PaymentsCompanion data) {
    return Payment(
      id: data.id.present ? data.id.value : this.id,
      unitId: data.unitId.present ? data.unitId.value : this.unitId,
      year: data.year.present ? data.year.value : this.year,
      month: data.month.present ? data.month.value : this.month,
      amount: data.amount.present ? data.amount.value : this.amount,
      paidOn: data.paidOn.present ? data.paidOn.value : this.paidOn,
      method: data.method.present ? data.method.value : this.method,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Payment(')
          ..write('id: $id, ')
          ..write('unitId: $unitId, ')
          ..write('year: $year, ')
          ..write('month: $month, ')
          ..write('amount: $amount, ')
          ..write('paidOn: $paidOn, ')
          ..write('method: $method, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    unitId,
    year,
    month,
    amount,
    paidOn,
    method,
    note,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Payment &&
          other.id == this.id &&
          other.unitId == this.unitId &&
          other.year == this.year &&
          other.month == this.month &&
          other.amount == this.amount &&
          other.paidOn == this.paidOn &&
          other.method == this.method &&
          other.note == this.note &&
          other.createdAt == this.createdAt);
}

class PaymentsCompanion extends UpdateCompanion<Payment> {
  final Value<int> id;
  final Value<int> unitId;
  final Value<int> year;
  final Value<int> month;
  final Value<int> amount;
  final Value<DateTime?> paidOn;
  final Value<PayMethod> method;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  const PaymentsCompanion({
    this.id = const Value.absent(),
    this.unitId = const Value.absent(),
    this.year = const Value.absent(),
    this.month = const Value.absent(),
    this.amount = const Value.absent(),
    this.paidOn = const Value.absent(),
    this.method = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PaymentsCompanion.insert({
    this.id = const Value.absent(),
    required int unitId,
    required int year,
    required int month,
    required int amount,
    this.paidOn = const Value.absent(),
    this.method = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : unitId = Value(unitId),
       year = Value(year),
       month = Value(month),
       amount = Value(amount);
  static Insertable<Payment> custom({
    Expression<int>? id,
    Expression<int>? unitId,
    Expression<int>? year,
    Expression<int>? month,
    Expression<int>? amount,
    Expression<DateTime>? paidOn,
    Expression<String>? method,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (unitId != null) 'unit_id': unitId,
      if (year != null) 'year': year,
      if (month != null) 'month': month,
      if (amount != null) 'amount': amount,
      if (paidOn != null) 'paid_on': paidOn,
      if (method != null) 'method': method,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PaymentsCompanion copyWith({
    Value<int>? id,
    Value<int>? unitId,
    Value<int>? year,
    Value<int>? month,
    Value<int>? amount,
    Value<DateTime?>? paidOn,
    Value<PayMethod>? method,
    Value<String?>? note,
    Value<DateTime>? createdAt,
  }) {
    return PaymentsCompanion(
      id: id ?? this.id,
      unitId: unitId ?? this.unitId,
      year: year ?? this.year,
      month: month ?? this.month,
      amount: amount ?? this.amount,
      paidOn: paidOn ?? this.paidOn,
      method: method ?? this.method,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (unitId.present) {
      map['unit_id'] = Variable<int>(unitId.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (month.present) {
      map['month'] = Variable<int>(month.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (paidOn.present) {
      map['paid_on'] = Variable<DateTime>(paidOn.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(
        $PaymentsTable.$convertermethod.toSql(method.value),
      );
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PaymentsCompanion(')
          ..write('id: $id, ')
          ..write('unitId: $unitId, ')
          ..write('year: $year, ')
          ..write('month: $month, ')
          ..write('amount: $amount, ')
          ..write('paidOn: $paidOn, ')
          ..write('method: $method, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ChargesTable extends Charges with TableInfo<$ChargesTable, Charge> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChargesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _unitIdMeta = const VerificationMeta('unitId');
  @override
  late final GeneratedColumn<int> unitId = GeneratedColumn<int>(
    'unit_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES units (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _monthMeta = const VerificationMeta('month');
  @override
  late final GeneratedColumn<int> month = GeneratedColumn<int>(
    'month',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _electricityMeta = const VerificationMeta(
    'electricity',
  );
  @override
  late final GeneratedColumn<int> electricity = GeneratedColumn<int>(
    'electricity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _waterMeta = const VerificationMeta('water');
  @override
  late final GeneratedColumn<int> water = GeneratedColumn<int>(
    'water',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _serviceMeta = const VerificationMeta(
    'service',
  );
  @override
  late final GeneratedColumn<int> service = GeneratedColumn<int>(
    'service',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    unitId,
    year,
    month,
    electricity,
    water,
    service,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'charges';
  @override
  VerificationContext validateIntegrity(
    Insertable<Charge> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('unit_id')) {
      context.handle(
        _unitIdMeta,
        unitId.isAcceptableOrUnknown(data['unit_id']!, _unitIdMeta),
      );
    } else if (isInserting) {
      context.missing(_unitIdMeta);
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    } else if (isInserting) {
      context.missing(_yearMeta);
    }
    if (data.containsKey('month')) {
      context.handle(
        _monthMeta,
        month.isAcceptableOrUnknown(data['month']!, _monthMeta),
      );
    } else if (isInserting) {
      context.missing(_monthMeta);
    }
    if (data.containsKey('electricity')) {
      context.handle(
        _electricityMeta,
        electricity.isAcceptableOrUnknown(
          data['electricity']!,
          _electricityMeta,
        ),
      );
    }
    if (data.containsKey('water')) {
      context.handle(
        _waterMeta,
        water.isAcceptableOrUnknown(data['water']!, _waterMeta),
      );
    }
    if (data.containsKey('service')) {
      context.handle(
        _serviceMeta,
        service.isAcceptableOrUnknown(data['service']!, _serviceMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {unitId, year, month},
  ];
  @override
  Charge map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Charge(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      unitId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_id'],
      )!,
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      )!,
      month: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}month'],
      )!,
      electricity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}electricity'],
      )!,
      water: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}water'],
      )!,
      service: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}service'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ChargesTable createAlias(String alias) {
    return $ChargesTable(attachedDatabase, alias);
  }
}

class Charge extends DataClass implements Insertable<Charge> {
  final int id;
  final int unitId;
  final int year;
  final int month;
  final int electricity;
  final int water;
  final int service;
  final DateTime createdAt;
  const Charge({
    required this.id,
    required this.unitId,
    required this.year,
    required this.month,
    required this.electricity,
    required this.water,
    required this.service,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['unit_id'] = Variable<int>(unitId);
    map['year'] = Variable<int>(year);
    map['month'] = Variable<int>(month);
    map['electricity'] = Variable<int>(electricity);
    map['water'] = Variable<int>(water);
    map['service'] = Variable<int>(service);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ChargesCompanion toCompanion(bool nullToAbsent) {
    return ChargesCompanion(
      id: Value(id),
      unitId: Value(unitId),
      year: Value(year),
      month: Value(month),
      electricity: Value(electricity),
      water: Value(water),
      service: Value(service),
      createdAt: Value(createdAt),
    );
  }

  factory Charge.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Charge(
      id: serializer.fromJson<int>(json['id']),
      unitId: serializer.fromJson<int>(json['unitId']),
      year: serializer.fromJson<int>(json['year']),
      month: serializer.fromJson<int>(json['month']),
      electricity: serializer.fromJson<int>(json['electricity']),
      water: serializer.fromJson<int>(json['water']),
      service: serializer.fromJson<int>(json['service']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'unitId': serializer.toJson<int>(unitId),
      'year': serializer.toJson<int>(year),
      'month': serializer.toJson<int>(month),
      'electricity': serializer.toJson<int>(electricity),
      'water': serializer.toJson<int>(water),
      'service': serializer.toJson<int>(service),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Charge copyWith({
    int? id,
    int? unitId,
    int? year,
    int? month,
    int? electricity,
    int? water,
    int? service,
    DateTime? createdAt,
  }) => Charge(
    id: id ?? this.id,
    unitId: unitId ?? this.unitId,
    year: year ?? this.year,
    month: month ?? this.month,
    electricity: electricity ?? this.electricity,
    water: water ?? this.water,
    service: service ?? this.service,
    createdAt: createdAt ?? this.createdAt,
  );
  Charge copyWithCompanion(ChargesCompanion data) {
    return Charge(
      id: data.id.present ? data.id.value : this.id,
      unitId: data.unitId.present ? data.unitId.value : this.unitId,
      year: data.year.present ? data.year.value : this.year,
      month: data.month.present ? data.month.value : this.month,
      electricity: data.electricity.present
          ? data.electricity.value
          : this.electricity,
      water: data.water.present ? data.water.value : this.water,
      service: data.service.present ? data.service.value : this.service,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Charge(')
          ..write('id: $id, ')
          ..write('unitId: $unitId, ')
          ..write('year: $year, ')
          ..write('month: $month, ')
          ..write('electricity: $electricity, ')
          ..write('water: $water, ')
          ..write('service: $service, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    unitId,
    year,
    month,
    electricity,
    water,
    service,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Charge &&
          other.id == this.id &&
          other.unitId == this.unitId &&
          other.year == this.year &&
          other.month == this.month &&
          other.electricity == this.electricity &&
          other.water == this.water &&
          other.service == this.service &&
          other.createdAt == this.createdAt);
}

class ChargesCompanion extends UpdateCompanion<Charge> {
  final Value<int> id;
  final Value<int> unitId;
  final Value<int> year;
  final Value<int> month;
  final Value<int> electricity;
  final Value<int> water;
  final Value<int> service;
  final Value<DateTime> createdAt;
  const ChargesCompanion({
    this.id = const Value.absent(),
    this.unitId = const Value.absent(),
    this.year = const Value.absent(),
    this.month = const Value.absent(),
    this.electricity = const Value.absent(),
    this.water = const Value.absent(),
    this.service = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ChargesCompanion.insert({
    this.id = const Value.absent(),
    required int unitId,
    required int year,
    required int month,
    this.electricity = const Value.absent(),
    this.water = const Value.absent(),
    this.service = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : unitId = Value(unitId),
       year = Value(year),
       month = Value(month);
  static Insertable<Charge> custom({
    Expression<int>? id,
    Expression<int>? unitId,
    Expression<int>? year,
    Expression<int>? month,
    Expression<int>? electricity,
    Expression<int>? water,
    Expression<int>? service,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (unitId != null) 'unit_id': unitId,
      if (year != null) 'year': year,
      if (month != null) 'month': month,
      if (electricity != null) 'electricity': electricity,
      if (water != null) 'water': water,
      if (service != null) 'service': service,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ChargesCompanion copyWith({
    Value<int>? id,
    Value<int>? unitId,
    Value<int>? year,
    Value<int>? month,
    Value<int>? electricity,
    Value<int>? water,
    Value<int>? service,
    Value<DateTime>? createdAt,
  }) {
    return ChargesCompanion(
      id: id ?? this.id,
      unitId: unitId ?? this.unitId,
      year: year ?? this.year,
      month: month ?? this.month,
      electricity: electricity ?? this.electricity,
      water: water ?? this.water,
      service: service ?? this.service,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (unitId.present) {
      map['unit_id'] = Variable<int>(unitId.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (month.present) {
      map['month'] = Variable<int>(month.value);
    }
    if (electricity.present) {
      map['electricity'] = Variable<int>(electricity.value);
    }
    if (water.present) {
      map['water'] = Variable<int>(water.value);
    }
    if (service.present) {
      map['service'] = Variable<int>(service.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChargesCompanion(')
          ..write('id: $id, ')
          ..write('unitId: $unitId, ')
          ..write('year: $year, ')
          ..write('month: $month, ')
          ..write('electricity: $electricity, ')
          ..write('water: $water, ')
          ..write('service: $service, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UnitsTable units = $UnitsTable(this);
  late final $PaymentsTable payments = $PaymentsTable(this);
  late final $ChargesTable charges = $ChargesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    units,
    payments,
    charges,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'units',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('payments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'units',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('charges', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$UnitsTableCreateCompanionBuilder =
    UnitsCompanion Function({
      Value<int> id,
      Value<String?> cloudId,
      required String code,
      required String tenantName,
      Value<String> businessType,
      required int monthlyRent,
      Value<String?> phone,
      Value<String?> notes,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime?> startedOn,
      Value<DateTime?> lastRaisedOn,
      Value<int> depositAmount,
      Value<bool> depositRefunded,
      Value<DateTime?> depositRefundedOn,
    });
typedef $$UnitsTableUpdateCompanionBuilder =
    UnitsCompanion Function({
      Value<int> id,
      Value<String?> cloudId,
      Value<String> code,
      Value<String> tenantName,
      Value<String> businessType,
      Value<int> monthlyRent,
      Value<String?> phone,
      Value<String?> notes,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime?> startedOn,
      Value<DateTime?> lastRaisedOn,
      Value<int> depositAmount,
      Value<bool> depositRefunded,
      Value<DateTime?> depositRefundedOn,
    });

final class $$UnitsTableReferences
    extends BaseReferences<_$AppDatabase, $UnitsTable, Unit> {
  $$UnitsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PaymentsTable, List<Payment>> _paymentsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.payments,
    aliasName: $_aliasNameGenerator(db.units.id, db.payments.unitId),
  );

  $$PaymentsTableProcessedTableManager get paymentsRefs {
    final manager = $$PaymentsTableTableManager(
      $_db,
      $_db.payments,
    ).filter((f) => f.unitId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_paymentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ChargesTable, List<Charge>> _chargesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.charges,
    aliasName: $_aliasNameGenerator(db.units.id, db.charges.unitId),
  );

  $$ChargesTableProcessedTableManager get chargesRefs {
    final manager = $$ChargesTableTableManager(
      $_db,
      $_db.charges,
    ).filter((f) => f.unitId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_chargesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UnitsTableFilterComposer extends Composer<_$AppDatabase, $UnitsTable> {
  $$UnitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudId => $composableBuilder(
    column: $table.cloudId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tenantName => $composableBuilder(
    column: $table.tenantName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessType => $composableBuilder(
    column: $table.businessType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get monthlyRent => $composableBuilder(
    column: $table.monthlyRent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedOn => $composableBuilder(
    column: $table.startedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastRaisedOn => $composableBuilder(
    column: $table.lastRaisedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get depositAmount => $composableBuilder(
    column: $table.depositAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get depositRefunded => $composableBuilder(
    column: $table.depositRefunded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get depositRefundedOn => $composableBuilder(
    column: $table.depositRefundedOn,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> paymentsRefs(
    Expression<bool> Function($$PaymentsTableFilterComposer f) f,
  ) {
    final $$PaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payments,
      getReferencedColumn: (t) => t.unitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentsTableFilterComposer(
            $db: $db,
            $table: $db.payments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> chargesRefs(
    Expression<bool> Function($$ChargesTableFilterComposer f) f,
  ) {
    final $$ChargesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.charges,
      getReferencedColumn: (t) => t.unitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChargesTableFilterComposer(
            $db: $db,
            $table: $db.charges,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UnitsTableOrderingComposer
    extends Composer<_$AppDatabase, $UnitsTable> {
  $$UnitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudId => $composableBuilder(
    column: $table.cloudId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tenantName => $composableBuilder(
    column: $table.tenantName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessType => $composableBuilder(
    column: $table.businessType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get monthlyRent => $composableBuilder(
    column: $table.monthlyRent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedOn => $composableBuilder(
    column: $table.startedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastRaisedOn => $composableBuilder(
    column: $table.lastRaisedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get depositAmount => $composableBuilder(
    column: $table.depositAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get depositRefunded => $composableBuilder(
    column: $table.depositRefunded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get depositRefundedOn => $composableBuilder(
    column: $table.depositRefundedOn,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UnitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UnitsTable> {
  $$UnitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cloudId =>
      $composableBuilder(column: $table.cloudId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get tenantName => $composableBuilder(
    column: $table.tenantName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get businessType => $composableBuilder(
    column: $table.businessType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get monthlyRent => $composableBuilder(
    column: $table.monthlyRent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get startedOn =>
      $composableBuilder(column: $table.startedOn, builder: (column) => column);

  GeneratedColumn<DateTime> get lastRaisedOn => $composableBuilder(
    column: $table.lastRaisedOn,
    builder: (column) => column,
  );

  GeneratedColumn<int> get depositAmount => $composableBuilder(
    column: $table.depositAmount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get depositRefunded => $composableBuilder(
    column: $table.depositRefunded,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get depositRefundedOn => $composableBuilder(
    column: $table.depositRefundedOn,
    builder: (column) => column,
  );

  Expression<T> paymentsRefs<T extends Object>(
    Expression<T> Function($$PaymentsTableAnnotationComposer a) f,
  ) {
    final $$PaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payments,
      getReferencedColumn: (t) => t.unitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.payments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> chargesRefs<T extends Object>(
    Expression<T> Function($$ChargesTableAnnotationComposer a) f,
  ) {
    final $$ChargesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.charges,
      getReferencedColumn: (t) => t.unitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChargesTableAnnotationComposer(
            $db: $db,
            $table: $db.charges,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UnitsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UnitsTable,
          Unit,
          $$UnitsTableFilterComposer,
          $$UnitsTableOrderingComposer,
          $$UnitsTableAnnotationComposer,
          $$UnitsTableCreateCompanionBuilder,
          $$UnitsTableUpdateCompanionBuilder,
          (Unit, $$UnitsTableReferences),
          Unit,
          PrefetchHooks Function({bool paymentsRefs, bool chargesRefs})
        > {
  $$UnitsTableTableManager(_$AppDatabase db, $UnitsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UnitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UnitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UnitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> cloudId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> tenantName = const Value.absent(),
                Value<String> businessType = const Value.absent(),
                Value<int> monthlyRent = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> startedOn = const Value.absent(),
                Value<DateTime?> lastRaisedOn = const Value.absent(),
                Value<int> depositAmount = const Value.absent(),
                Value<bool> depositRefunded = const Value.absent(),
                Value<DateTime?> depositRefundedOn = const Value.absent(),
              }) => UnitsCompanion(
                id: id,
                cloudId: cloudId,
                code: code,
                tenantName: tenantName,
                businessType: businessType,
                monthlyRent: monthlyRent,
                phone: phone,
                notes: notes,
                isActive: isActive,
                createdAt: createdAt,
                startedOn: startedOn,
                lastRaisedOn: lastRaisedOn,
                depositAmount: depositAmount,
                depositRefunded: depositRefunded,
                depositRefundedOn: depositRefundedOn,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> cloudId = const Value.absent(),
                required String code,
                required String tenantName,
                Value<String> businessType = const Value.absent(),
                required int monthlyRent,
                Value<String?> phone = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> startedOn = const Value.absent(),
                Value<DateTime?> lastRaisedOn = const Value.absent(),
                Value<int> depositAmount = const Value.absent(),
                Value<bool> depositRefunded = const Value.absent(),
                Value<DateTime?> depositRefundedOn = const Value.absent(),
              }) => UnitsCompanion.insert(
                id: id,
                cloudId: cloudId,
                code: code,
                tenantName: tenantName,
                businessType: businessType,
                monthlyRent: monthlyRent,
                phone: phone,
                notes: notes,
                isActive: isActive,
                createdAt: createdAt,
                startedOn: startedOn,
                lastRaisedOn: lastRaisedOn,
                depositAmount: depositAmount,
                depositRefunded: depositRefunded,
                depositRefundedOn: depositRefundedOn,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$UnitsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({paymentsRefs = false, chargesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (paymentsRefs) db.payments,
                if (chargesRefs) db.charges,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (paymentsRefs)
                    await $_getPrefetchedData<Unit, $UnitsTable, Payment>(
                      currentTable: table,
                      referencedTable: $$UnitsTableReferences
                          ._paymentsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$UnitsTableReferences(db, table, p0).paymentsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.unitId == item.id),
                      typedResults: items,
                    ),
                  if (chargesRefs)
                    await $_getPrefetchedData<Unit, $UnitsTable, Charge>(
                      currentTable: table,
                      referencedTable: $$UnitsTableReferences._chargesRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$UnitsTableReferences(db, table, p0).chargesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.unitId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$UnitsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UnitsTable,
      Unit,
      $$UnitsTableFilterComposer,
      $$UnitsTableOrderingComposer,
      $$UnitsTableAnnotationComposer,
      $$UnitsTableCreateCompanionBuilder,
      $$UnitsTableUpdateCompanionBuilder,
      (Unit, $$UnitsTableReferences),
      Unit,
      PrefetchHooks Function({bool paymentsRefs, bool chargesRefs})
    >;
typedef $$PaymentsTableCreateCompanionBuilder =
    PaymentsCompanion Function({
      Value<int> id,
      required int unitId,
      required int year,
      required int month,
      required int amount,
      Value<DateTime?> paidOn,
      Value<PayMethod> method,
      Value<String?> note,
      Value<DateTime> createdAt,
    });
typedef $$PaymentsTableUpdateCompanionBuilder =
    PaymentsCompanion Function({
      Value<int> id,
      Value<int> unitId,
      Value<int> year,
      Value<int> month,
      Value<int> amount,
      Value<DateTime?> paidOn,
      Value<PayMethod> method,
      Value<String?> note,
      Value<DateTime> createdAt,
    });

final class $$PaymentsTableReferences
    extends BaseReferences<_$AppDatabase, $PaymentsTable, Payment> {
  $$PaymentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UnitsTable _unitIdTable(_$AppDatabase db) => db.units.createAlias(
    $_aliasNameGenerator(db.payments.unitId, db.units.id),
  );

  $$UnitsTableProcessedTableManager get unitId {
    final $_column = $_itemColumn<int>('unit_id')!;

    final manager = $$UnitsTableTableManager(
      $_db,
      $_db.units,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_unitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get month => $composableBuilder(
    column: $table.month,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get paidOn => $composableBuilder(
    column: $table.paidOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PayMethod, PayMethod, String> get method =>
      $composableBuilder(
        column: $table.method,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$UnitsTableFilterComposer get unitId {
    final $$UnitsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.unitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableFilterComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get month => $composableBuilder(
    column: $table.month,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get paidOn => $composableBuilder(
    column: $table.paidOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$UnitsTableOrderingComposer get unitId {
    final $$UnitsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.unitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableOrderingComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get month =>
      $composableBuilder(column: $table.month, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<DateTime> get paidOn =>
      $composableBuilder(column: $table.paidOn, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PayMethod, String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$UnitsTableAnnotationComposer get unitId {
    final $$UnitsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.unitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableAnnotationComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PaymentsTable,
          Payment,
          $$PaymentsTableFilterComposer,
          $$PaymentsTableOrderingComposer,
          $$PaymentsTableAnnotationComposer,
          $$PaymentsTableCreateCompanionBuilder,
          $$PaymentsTableUpdateCompanionBuilder,
          (Payment, $$PaymentsTableReferences),
          Payment,
          PrefetchHooks Function({bool unitId})
        > {
  $$PaymentsTableTableManager(_$AppDatabase db, $PaymentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> unitId = const Value.absent(),
                Value<int> year = const Value.absent(),
                Value<int> month = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<DateTime?> paidOn = const Value.absent(),
                Value<PayMethod> method = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PaymentsCompanion(
                id: id,
                unitId: unitId,
                year: year,
                month: month,
                amount: amount,
                paidOn: paidOn,
                method: method,
                note: note,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int unitId,
                required int year,
                required int month,
                required int amount,
                Value<DateTime?> paidOn = const Value.absent(),
                Value<PayMethod> method = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PaymentsCompanion.insert(
                id: id,
                unitId: unitId,
                year: year,
                month: month,
                amount: amount,
                paidOn: paidOn,
                method: method,
                note: note,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PaymentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({unitId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (unitId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.unitId,
                                referencedTable: $$PaymentsTableReferences
                                    ._unitIdTable(db),
                                referencedColumn: $$PaymentsTableReferences
                                    ._unitIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PaymentsTable,
      Payment,
      $$PaymentsTableFilterComposer,
      $$PaymentsTableOrderingComposer,
      $$PaymentsTableAnnotationComposer,
      $$PaymentsTableCreateCompanionBuilder,
      $$PaymentsTableUpdateCompanionBuilder,
      (Payment, $$PaymentsTableReferences),
      Payment,
      PrefetchHooks Function({bool unitId})
    >;
typedef $$ChargesTableCreateCompanionBuilder =
    ChargesCompanion Function({
      Value<int> id,
      required int unitId,
      required int year,
      required int month,
      Value<int> electricity,
      Value<int> water,
      Value<int> service,
      Value<DateTime> createdAt,
    });
typedef $$ChargesTableUpdateCompanionBuilder =
    ChargesCompanion Function({
      Value<int> id,
      Value<int> unitId,
      Value<int> year,
      Value<int> month,
      Value<int> electricity,
      Value<int> water,
      Value<int> service,
      Value<DateTime> createdAt,
    });

final class $$ChargesTableReferences
    extends BaseReferences<_$AppDatabase, $ChargesTable, Charge> {
  $$ChargesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UnitsTable _unitIdTable(_$AppDatabase db) => db.units.createAlias(
    $_aliasNameGenerator(db.charges.unitId, db.units.id),
  );

  $$UnitsTableProcessedTableManager get unitId {
    final $_column = $_itemColumn<int>('unit_id')!;

    final manager = $$UnitsTableTableManager(
      $_db,
      $_db.units,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_unitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ChargesTableFilterComposer
    extends Composer<_$AppDatabase, $ChargesTable> {
  $$ChargesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get month => $composableBuilder(
    column: $table.month,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get electricity => $composableBuilder(
    column: $table.electricity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get water => $composableBuilder(
    column: $table.water,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get service => $composableBuilder(
    column: $table.service,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$UnitsTableFilterComposer get unitId {
    final $$UnitsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.unitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableFilterComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChargesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChargesTable> {
  $$ChargesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get month => $composableBuilder(
    column: $table.month,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get electricity => $composableBuilder(
    column: $table.electricity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get water => $composableBuilder(
    column: $table.water,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get service => $composableBuilder(
    column: $table.service,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$UnitsTableOrderingComposer get unitId {
    final $$UnitsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.unitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableOrderingComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChargesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChargesTable> {
  $$ChargesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get month =>
      $composableBuilder(column: $table.month, builder: (column) => column);

  GeneratedColumn<int> get electricity => $composableBuilder(
    column: $table.electricity,
    builder: (column) => column,
  );

  GeneratedColumn<int> get water =>
      $composableBuilder(column: $table.water, builder: (column) => column);

  GeneratedColumn<int> get service =>
      $composableBuilder(column: $table.service, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$UnitsTableAnnotationComposer get unitId {
    final $$UnitsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.unitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableAnnotationComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChargesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChargesTable,
          Charge,
          $$ChargesTableFilterComposer,
          $$ChargesTableOrderingComposer,
          $$ChargesTableAnnotationComposer,
          $$ChargesTableCreateCompanionBuilder,
          $$ChargesTableUpdateCompanionBuilder,
          (Charge, $$ChargesTableReferences),
          Charge,
          PrefetchHooks Function({bool unitId})
        > {
  $$ChargesTableTableManager(_$AppDatabase db, $ChargesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChargesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChargesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChargesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> unitId = const Value.absent(),
                Value<int> year = const Value.absent(),
                Value<int> month = const Value.absent(),
                Value<int> electricity = const Value.absent(),
                Value<int> water = const Value.absent(),
                Value<int> service = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ChargesCompanion(
                id: id,
                unitId: unitId,
                year: year,
                month: month,
                electricity: electricity,
                water: water,
                service: service,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int unitId,
                required int year,
                required int month,
                Value<int> electricity = const Value.absent(),
                Value<int> water = const Value.absent(),
                Value<int> service = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ChargesCompanion.insert(
                id: id,
                unitId: unitId,
                year: year,
                month: month,
                electricity: electricity,
                water: water,
                service: service,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChargesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({unitId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (unitId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.unitId,
                                referencedTable: $$ChargesTableReferences
                                    ._unitIdTable(db),
                                referencedColumn: $$ChargesTableReferences
                                    ._unitIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ChargesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChargesTable,
      Charge,
      $$ChargesTableFilterComposer,
      $$ChargesTableOrderingComposer,
      $$ChargesTableAnnotationComposer,
      $$ChargesTableCreateCompanionBuilder,
      $$ChargesTableUpdateCompanionBuilder,
      (Charge, $$ChargesTableReferences),
      Charge,
      PrefetchHooks Function({bool unitId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db, _db.units);
  $$PaymentsTableTableManager get payments =>
      $$PaymentsTableTableManager(_db, _db.payments);
  $$ChargesTableTableManager get charges =>
      $$ChargesTableTableManager(_db, _db.charges);
}
