const win32 = @import("win32.zig");
const assert = @import("../../assert.zig").assert;

const HANDLE = win32.HANDLE;
const USHORT = win32.USHORT;
const LONG = win32.LONG;
const ULONG = win32.ULONG;
const ULONGLONG = win32.ULONGLONG;
const LARGE_INTEGER = win32.LARGE_INTEGER;
const PWSTR = win32.PWSTR;
const PCWSTR = win32.PCWSTR;
const PVOID = win32.PVOID;
const LPVOID = win32.LPVOID;
const DWORD = win32.DWORD;
const BOOL = win32.BOOL;
const ULONG_PTR = win32.ULONG_PTR;

pub const NTSTATUS = @import("ntstatus.zig").NTSTATUS;
pub const CURRENT_PROCESS: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
pub const CURRENT_THREAD: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));

pub const LOGICAL = win32.BOOL;
comptime {
    assert(@sizeOf(LOGICAL) == @sizeOf(ULONG));
}

pub const OBJECT_ATTRIBUTES = extern struct {
    length: ULONG = @sizeOf(@This()),
    root_directory: ?HANDLE,
    object_name: *const UNICODE_STRING,
    attributes: FLAGS,
    security_descriptor: ?*anyopaque,
    security_quality_of_service: ?*anyopaque,

    pub const FLAGS = packed struct(ULONG) {
        __reserved0__: u1 = 0,
        INHERIT: bool = false,
        __reserved1__: u2 = 0,
        PERMANENT: bool = false,
        EXCLUSIVE: bool = false,
        CASE_INSENSITIVE: bool = false,
        OPENIF: bool = false,
        OPENLINK: bool = false,
        KERNEL_HANDLE: bool = false,
        FORCE_ACCESS_CHECK: bool = false,
        IGNORE_IMPERSONATED_DEVICEMAP: bool = false,
        DONT_REPARSE: bool = false,
        __reserved2__: u19 = 0,

        pub const default = FLAGS{ .CASE_INSENSITIVE = true };
    };
};

pub const PROCESS = struct {
    pub const INFOCLASS = enum(c_int) {
        /// q: PROCESS_BASIC_INFORMATION, PROCESS_EXTENDED_BASIC_INFORMATION
        BasicInformation,
        /// qs: QUOTA_LIMITS, QUOTA_LIMITS_EX
        QuotaLimits,
        /// q: IO_COUNTERS
        IoCounters,
        /// q: VM_COUNTERS, VM_COUNTERS_EX, VM_COUNTERS_EX2
        VmCounters,
        /// q: KERNEL_USER_TIMES // since VISTA
        Times,
        /// s: KPRIORITY
        BasePriority,
        /// s: PROCESS_RAISE_PRIORITY
        RaisePriority,
        /// q: HANDLE
        DebugPort,
        /// s: PROCESS_EXCEPTION_PORT (requires SeTcbPrivilege)
        ExceptionPort,
        /// s: PROCESS_ACCESS_TOKEN
        AccessToken,
        /// qs: PROCESS_LDT_INFORMATION // 10
        LdtInformation,
        /// s: PROCESS_LDT_SIZE
        LdtSize,
        /// qs: PROCESS_DEFAULT_HARD_ERROR_MODE
        DefaultHardErrorMode,
        /// s: PROCESS_IO_PORT_HANDLER_INFORMATION // (kernel-mode only)
        IoPortHandlers,
        /// q: POOLED_USAGE_AND_LIMITS
        PooledUsageAndLimits,
        /// qs: PROCESS_WS_WATCH_INFORMATION[]; s: void
        WorkingSetWatch,
        /// s: PROCESS_USER_MODE_IOPL (requires SeTcbPrivilege)
        UserModeIOPL,
        /// s: BOOLEAN
        EnableAlignmentFaultFixup,
        /// qs: PROCESS_PRIORITY_CLASS
        PriorityClass,
        /// qs: ULONG (requires SeTcbPrivilege) (VdmAllowed)
        Wx86Information,
        /// q: ULONG, PROCESS_HANDLE_INFORMATION // 20
        HandleCount,
        /// qs: KAFFINITY, qs: GROUP_AFFINITY
        AffinityMask,
        /// qs: PROCESS_PRIORITY_BOOST
        PriorityBoost,
        /// qs: PROCESS_DEVICEMAP_INFORMATION, PROCESS_DEVICEMAP_INFORMATION_EX
        DeviceMap,
        /// qs: PROCESS_SESSION_INFORMATION
        SessionInformation,
        /// s: PROCESS_FOREGROUND_BACKGROUND
        ForegroundInformation,
        /// q: ULONG_PTR
        Wow64Information,
        /// q: UNICODE_STRING
        ImageFileName,
        /// q: PROCESS_LUID_DEVICE_MAPS_ENABLED
        LUIDDeviceMapsEnabled,
        /// qs: ULONG
        BreakOnTermination,
        /// q: HANDLE // 30
        DebugObjectHandle,
        /// qs: PROCESS_DEBUG_FLAGS
        DebugFlags,
        /// qs: PROCESS_HANDLE_TRACING_QUERY; s: PROCESS_HANDLE_TRACING_ENABLE[_EX] or void to disable
        HandleTracing,
        /// qs: IO_PRIORITY_HINT (s: requires SeIncreaseBasePriorityPrivilege)
        IoPriority,
        /// qs: PROCESS_EXECUTE_FLAGS
        ExecuteFlags,
        /// s: PROCESS_TLS_INFORMATION // ProcessResourceManagement
        TlsInformation,
        /// q: ULONG
        Cookie,
        /// q: SECTION_IMAGE_INFORMATION
        ImageInformation,
        /// q: PROCESS_CYCLE_TIME_INFORMATION // since VISTA
        CycleTime,
        /// qs: PAGE_PRIORITY_INFORMATION
        PagePriority,
        /// s: PVOID or PROCESS_INSTRUMENTATION_CALLBACK_INFORMATION // 40
        InstrumentationCallback,
        /// s: PROCESS_STACK_ALLOCATION_INFORMATION, PROCESS_STACK_ALLOCATION_INFORMATION_EX
        ThreadStackAllocation,
        /// qs: PROCESS_WS_WATCH_INFORMATION_EX[]; s: void
        WorkingSetWatchEx,
        /// q: UNICODE_STRING
        ImageFileNameWin32,
        /// q: HANDLE (input)
        ImageFileMapping,
        /// qs: PROCESS_AFFINITY_UPDATE_MODE
        AffinityUpdateMode,
        /// qs: PROCESS_MEMORY_ALLOCATION_MODE
        MemoryAllocationMode,
        /// q: PROCESS_GROUP_INFORMATION
        GroupInformation,
        /// s: ULONG
        TokenVirtualizationEnabled,
        /// qs: PROCESS_CONSOLE_HOST_PROCESS_INFORMATION
        ConsoleHostProcess,
        /// q: PROCESS_WINDOW_INFORMATION // 50
        WindowInformation,
        /// q: PROCESS_HANDLE_SNAPSHOT_INFORMATION // since WIN8
        HandleInformation,
        /// s: PROCESS_MITIGATION_POLICY_INFORMATION
        MitigationPolicy,
        /// s: PROCESS_DYNAMIC_FUNCTION_TABLE_INFORMATION
        DynamicFunctionTableInformation,
        /// qs: PROCESS_HANDLE_CHECKING_MODE; s: 0 disables, otherwise enables
        HandleCheckingMode,
        /// q: PROCESS_KEEPALIVE_COUNT_INFORMATION
        KeepAliveCount,
        /// s: PROCESS_REVOKE_FILE_HANDLES_INFORMATION
        RevokeFileHandles,
        /// s: PROCESS_WORKING_SET_CONTROL
        WorkingSetControl,
        /// q: ULONG[] // since WINBLUE
        HandleTable,
        /// qs: ULONG // KPROCESS->CheckStackExtents (CFG)
        CheckStackExtentsMode,
        /// q: UNICODE_STRING // 60
        CommandLineInformation,
        /// q: PS_PROTECTION
        ProtectionInformation,
        /// s: PROCESS_MEMORY_EXHAUSTION_INFO // since THRESHOLD
        MemoryExhaustion,
        /// s: PROCESS_FAULT_INFORMATION
        FaultInformation,
        /// q: PROCESS_TELEMETRY_ID_INFORMATION
        TelemetryIdInformation,
        /// qs: PROCESS_COMMIT_RELEASE_INFORMATION
        CommitReleaseInformation,
        /// qs: SYSTEM_CPU_SET_INFORMATION[5] // ProcessReserved1Information
        DefaultCpuSetsInformation,
        /// qs: SYSTEM_CPU_SET_INFORMATION[5] // ProcessReserved2Information
        AllowedCpuSetsInformation,
        /// s: void // EPROCESS->SubsystemProcess
        SubsystemProcess,
        /// q: PROCESS_JOB_MEMORY_INFO
        JobMemoryInformation,
        /// qs: BOOLEAN; s: void // ETW // since THRESHOLD2 // 70
        InPrivate,
        /// qs: PROCESS_RAISE_UM_EXCEPTION_ON_INVALID_HANDLE_CLOSE; s: 0 disables, otherwise enables
        RaiseUMExceptionOnInvalidHandleClose,
        /// qs: PROCESS_IUM_CHALLENGE_RESPONSE
        IumChallengeResponse,
        /// q: PROCESS_CHILD_PROCESS_INFORMATION
        ChildProcessInformation,
        /// qs: BOOLEAN; s: BOOLEAN (requires SeTcbPrivilege)
        HighGraphicsPriorityInformation,
        /// q: SUBSYSTEM_INFORMATION_TYPE // since REDSTONE2
        SubsystemInformation,
        /// q: PROCESS_ENERGY_VALUES, PROCESS_EXTENDED_ENERGY_VALUES, PROCESS_EXTENDED_ENERGY_VALUES_V1
        EnergyValues,
        /// qs: POWER_THROTTLING_PROCESS_STATE
        PowerThrottlingState,
        /// qs: Obsolete // PROCESS_ACTIVITY_THROTTLE_POLICY // ProcessReserved3Information
        ActivityThrottlePolicy,
        /// q: WIN32K_SYSCALL_FILTER
        Win32kSyscallFilterInformation,
        /// s: BOOLEAN // 80
        DisableSystemAllowedCpuSets,
        /// q: PROCESS_WAKE_INFORMATION // (kernel-mode only)
        WakeInformation,
        /// qs: PROCESS_ENERGY_TRACKING_STATE
        EnergyTrackingState,
        /// s: MANAGE_WRITES_TO_EXECUTABLE_MEMORY // since REDSTONE3
        ManageWritesToExecutableMemory,
        /// q: ULONG
        CaptureTrustletLiveDump,
        /// qs: TELEMETRY_COVERAGE_HEADER; s: TELEMETRY_COVERAGE_POINT
        TelemetryCoverage,
        /// qs: Obsolete
        EnclaveInformation,
        /// qs: PROCESS_READWRITEVM_LOGGING_INFORMATION
        EnableReadWriteVmLogging,
        /// q: PROCESS_UPTIME_INFORMATION
        UptimeInformation,
        /// q: HANDLE
        ImageSection,
        /// s: PROCESS_DEBUG_AUTH_INFORMATION // CiTool.exe -- device-id // PplDebugAuthorization // since RS4 // 90
        DebugAuthInformation,
        /// s: PROCESS_SYSTEM_RESOURCE_MANAGEMENT
        SystemResourceManagement,
        /// q: ULONGLONG
        SequenceNumber,
        /// qs: Obsolete // since RS5
        LoaderDetour,
        /// q: PROCESS_SECURITY_DOMAIN_INFORMATION
        SecurityDomainInformation,
        /// s: PROCESS_COMBINE_SECURITY_DOMAINS_INFORMATION
        CombineSecurityDomainsInformation,
        /// q: PROCESS_LOGGING_INFORMATION
        EnableLogging,
        /// qs: PROCESS_LEAP_SECOND_INFORMATION
        LeapSecondInformation,
        /// s: PROCESS_FIBER_SHADOW_STACK_ALLOCATION_INFORMATION // since 19H1
        FiberShadowStackAllocation,
        /// s: PROCESS_FREE_FIBER_SHADOW_STACK_ALLOCATION_INFORMATION
        FreeFiberShadowStackAllocation,
        /// s: PROCESS_SYSCALL_PROVIDER_INFORMATION // since 20H1 // 100
        AltSystemCallInformation,
        /// s: PROCESS_DYNAMIC_EH_CONTINUATION_TARGETS_INFORMATION
        DynamicEHContinuationTargets,
        /// s: PROCESS_DYNAMIC_ENFORCED_ADDRESS_RANGE_INFORMATION // since 20H2
        DynamicEnforcedCetCompatibleRanges,
        /// qs: Obsolete // since WIN11
        CreateStateChange,
        /// qs: Obsolete
        ApplyStateChange,
        /// s: ULONG64 // EnableProcessOptionalXStateFeatures
        EnableOptionalXStateFeatures,
        /// qs: OVERRIDE_PREFETCH_PARAMETER // App Launch Prefetch (ALPF) // since 22H1
        AltPrefetchParam,
        /// s: HANDLE[]
        AssignCpuPartitions,
        /// s: PROCESS_PRIORITY_CLASS_EX
        PriorityClassEx,
        /// q: PROCESS_MEMBERSHIP_INFORMATION
        MembershipInformation,
        /// q: IO_PRIORITY_HINT // 110
        EffectiveIoPriority,
        /// q: ULONG
        EffectivePagePriority,
        /// s: PROCESS_SCHEDULER_SHARED_DATA_SLOT_INFORMATION // since 24H2
        SchedulerSharedData,
        /// qs: no input buffer, length 0 on set, current process only
        SlistRollbackInformation,
        /// q: PROCESS_NETWORK_COUNTERS
        NetworkIoCounters,
        /// q: PROCESS_TEB_VALUE_INFORMATION // NtCurrentProcess
        FindFirstThreadByTebValue,
        /// qs: Obsolete // since 25H2
        EnclaveAddressSpaceRestriction,
        /// qs: Obsolete // PROCESS_AVAILABLE_CPUS_INFORMATION
        AvailableCpus,

        MaxProcessInfoClass,
    };
};

pub const THREAD = struct {
    pub const INFOCLASS = enum(c_int) {
        /// q: THREAD_BASIC_INFORMATION
        BasicInformation,
        /// q: KERNEL_USER_TIMES // since VISTA
        Times,
        /// s: KPRIORITY (requires SeIncreaseBasePriorityPrivilege)
        Priority,
        /// s: KPRIORITY
        BasePriority,
        /// s: KAFFINITY
        AffinityMask,
        /// s: HANDLE
        ImpersonationToken,
        /// q: DESCRIPTOR_TABLE_ENTRY (or WOW64_DESCRIPTOR_TABLE_ENTRY)
        DescriptorTableEntry,
        /// s: BOOLEAN
        EnableAlignmentFaultFixup,
        /// q: Obsolete
        EventPair,
        /// q: PVOID
        QuerySetWin32StartAddress,
        /// s: ULONG // TlsIndex // 10
        ZeroTlsCell,
        /// q: LARGE_INTEGER
        PerformanceCount,
        /// q: ULONG
        AmILastThread,
        /// s: ULONG
        IdealProcessor,
        /// qs: ULONG
        PriorityBoost,
        /// s: ULONG_PTR
        SetTlsArrayAddress,
        /// q: ULONG
        IsIoPending,
        /// qs: BOOLEAN
        HideFromDebugger,
        /// qs: ULONG
        BreakOnTermination,
        /// s: void // NtCurrentThread // NPX/FPU
        SwitchLegacyState,
        /// q: ULONG // 20
        IsTerminated,
        /// q: THREAD_LAST_SYSCALL_INFORMATION
        LastSystemCall,
        /// qs: IO_PRIORITY_HINT (s: requires SeIncreaseBasePriorityPrivilege)
        IoPriority,
        /// q: THREAD_CYCLE_TIME_INFORMATION (requires THREAD_QUERY_LIMITED_INFORMATION)
        CycleTime,
        /// qs: PAGE_PRIORITY_INFORMATION
        PagePriority,
        /// q: LONG
        ActualBasePriority,
        /// q: THREAD_TEB_INFORMATION (requires THREAD_GET_CONTEXT + THREAD_SET_CONTEXT)
        TebInformation,
        /// q: Obsolete
        CSwitchMon,
        /// q: Obsolete
        CSwitchPmu,
        /// qs: WOW64_CONTEXT, ARM_NT_CONTEXT since 20H1
        Wow64Context,
        /// qs: GROUP_AFFINITY // 30
        GroupInformation,
        /// q: THREAD_UMS_INFORMATION // Obsolete
        UmsInformation,
        /// qs: THREAD_PROFILING_INFORMATION
        CounterProfiling,
        /// qs: PROCESSOR_NUMBER; s: previous PROCESSOR_NUMBER on return
        IdealProcessorEx,
        /// s: HANDLE // since WIN8
        CpuAccountingInformation,
        /// q: ULONG // since WINBLUE
        SuspendCount,
        /// qs: KHETERO_CPU_POLICY // since THRESHOLD
        HeterogeneousCpuPolicy,
        /// q: GUID
        ContainerId,
        /// qs: THREAD_NAME_INFORMATION (requires THREAD_SET_LIMITED_INFORMATION)
        NameInformation,
        /// qs: ULONG[]
        SelectedCpuSets,
        /// q: SYSTEM_THREAD_INFORMATION // 40
        SystemThreadInformation,
        /// q: GROUP_AFFINITY // since THRESHOLD2
        ActualGroupAffinity,
        /// qs: ULONG // NtCurrentThread
        DynamicCodePolicyInfo,
        /// qs: ULONG; s: 0 disables, otherwise enables // (requires SeDebugPrivilege and PsProtectedSignerAntimalware)
        ExplicitCaseSensitivity,
        /// q: RTL_WORK_ON_BEHALF_TICKET_EX; s: ALPC_WORK_ON_BEHALF_TICKET // NtCurrentThread
        WorkOnBehalfTicket,
        /// q: SUBSYSTEM_INFORMATION_TYPE // since REDSTONE2
        SubsystemInformation,
        /// s: ULONG
        DbgkWerReportActive,
        /// s: HANDLE (job object) // NtCurrentThread
        AttachContainer,
        /// s: MANAGE_WRITES_TO_EXECUTABLE_MEMORY // since REDSTONE3
        ManageWritesToExecutableMemory,
        /// qs: POWER_THROTTLING_THREAD_STATE // since REDSTONE3 (set), WIN11 22H2 (query)
        PowerThrottlingState,
        /// qs: THREAD_WORKLOAD_CLASS // since REDSTONE5 // 50
        WorkloadClass,
        /// s: Obsolete // since WIN11
        CreateStateChange,
        /// s: Obsolete
        ApplyStateChange,
        /// qs: ULONG // NtCurrentThread // since 22H1
        StrongerBadHandleChecks,
        /// q: IO_PRIORITY_HINT
        EffectiveIoPriority,
        /// q: ULONG
        EffectivePagePriority,
        /// s: THREAD_LOCK_OWNERSHIP // since 24H2
        UpdateLockOwnership,
        /// qs: THREAD_SCHEDULER_SHARED_DATA_SLOT_INFORMATION
        SchedulerSharedDataSlot,
        /// q: THREAD_TEB_INFORMATION (requires THREAD_GET_CONTEXT + THREAD_QUERY_INFORMATION)
        TebInformationAtomic,
        /// q: THREAD_INDEX_INFORMATION
        IndexInformation,

        MaxThreadInfoClass,
    };
};

pub const FILE = struct {
    pub const INFOCLASS = enum(c_int) {
        /// q: FILE_DIRECTORY_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex])
        DirectoryInformation = 1,
        /// q: FILE_FULL_DIR_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex])
        FullDirectoryInformation,
        /// q: FILE_BOTH_DIR_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex])
        BothDirectoryInformation,
        /// qs: FILE_BASIC_INFORMATION (q: requires FILE_READ_ATTRIBUTES; s: requires FILE_WRITE_ATTRIBUTES)
        BasicInformation,
        /// q: FILE_STANDARD_INFORMATION, FILE_STANDARD_INFORMATION_EX
        StandardInformation,
        /// q: FILE_INTERNAL_INFORMATION
        InternalInformation,
        /// q: FILE_EA_INFORMATION (requires FILE_READ_EA)
        EaInformation,
        /// q: FILE_ACCESS_INFORMATION
        AccessInformation,
        /// q: FILE_NAME_INFORMATION
        NameInformation,
        /// s: FILE_RENAME_INFORMATION (requires DELETE) // 10
        RenameInformation,
        /// s: FILE_LINK_INFORMATION
        LinkInformation,
        /// q: FILE_NAMES_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex])
        NamesInformation,
        /// s: FILE_DISPOSITION_INFORMATION (requires DELETE)
        DispositionInformation,
        /// qs: FILE_POSITION_INFORMATION (q: requires FILE_READ_ATTRIBUTES; s: requires FILE_WRITE_ATTRIBUTES)
        PositionInformation,
        /// q: FILE_FULL_EA_INFORMATION (requires FILE_READ_EA)
        FullEaInformation,
        /// qs: FILE_MODE_INFORMATION (q: requires FILE_READ_ATTRIBUTES; s: requires FILE_WRITE_ATTRIBUTES)
        ModeInformation,
        /// q: FILE_ALIGNMENT_INFORMATION
        AlignmentInformation,
        /// q: FILE_ALL_INFORMATION
        AllInformation,
        /// s: FILE_ALLOCATION_INFORMATION (requires FILE_WRITE_DATA)
        AllocationInformation,
        /// s: FILE_END_OF_FILE_INFORMATION (requires FILE_WRITE_DATA) // 20
        EndOfFileInformation,
        /// q: FILE_NAME_INFORMATION
        AlternateNameInformation,
        /// q: FILE_STREAM_INFORMATION
        StreamInformation,
        /// qs: FILE_PIPE_INFORMATION (q: requires FILE_READ_ATTRIBUTES; s: requires FILE_WRITE_ATTRIBUTES)
        PipeInformation,
        /// q: FILE_PIPE_LOCAL_INFORMATION
        PipeLocalInformation,
        /// qs: FILE_PIPE_REMOTE_INFORMATION (q: requires FILE_READ_ATTRIBUTES; s: requires FILE_WRITE_ATTRIBUTES)
        PipeRemoteInformation,
        /// q: FILE_MAILSLOT_QUERY_INFORMATION
        MailslotQueryInformation,
        /// s: FILE_MAILSLOT_SET_INFORMATION
        MailslotSetInformation,
        /// q: FILE_COMPRESSION_INFORMATION
        CompressionInformation,
        /// q: FILE_OBJECTID_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex])
        ObjectIdInformation,
        /// s: FILE_COMPLETION_INFORMATION // 30
        CompletionInformation,
        /// s: FILE_MOVE_CLUSTER_INFORMATION (requires FILE_WRITE_DATA)
        MoveClusterInformation,
        /// q: FILE_QUOTA_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex])
        QuotaInformation,
        /// q: FILE_REPARSE_POINT_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex])
        ReparsePointInformation,
        /// q: FILE_NETWORK_OPEN_INFORMATION
        NetworkOpenInformation,
        /// q: FILE_ATTRIBUTE_TAG_INFORMATION
        AttributeTagInformation,
        /// s: FILE_TRACKING_INFORMATION (requires FILE_WRITE_DATA)
        TrackingInformation,
        /// q: FILE_ID_BOTH_DIR_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex])
        IdBothDirectoryInformation,
        /// q: FILE_ID_FULL_DIR_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex])
        IdFullDirectoryInformation,
        /// s: FILE_VALID_DATA_LENGTH_INFORMATION (requires FILE_WRITE_DATA and/or SeManageVolumePrivilege)
        ValidDataLengthInformation,
        /// s: FILE_NAME_INFORMATION (requires DELETE) // 40
        ShortNameInformation,
        /// qs: FILE_IO_COMPLETION_NOTIFICATION_INFORMATION (q: requires FILE_READ_ATTRIBUTES; s: requires FILE_WRITE_ATTRIBUTES) // since VISTA
        IoCompletionNotificationInformation,
        /// s: FILE_IOSTATUSBLOCK_RANGE_INFORMATION (requires SeLockMemoryPrivilege)
        IoStatusBlockRangeInformation,
        /// qs: FILE_IO_PRIORITY_HINT_INFORMATION, FILE_IO_PRIORITY_HINT_INFORMATION_EX (q: requires FILE_READ_DATA)
        IoPriorityHintInformation,
        /// qs: FILE_SFIO_RESERVE_INFORMATION (q: requires FILE_READ_DATA)
        SfioReserveInformation,
        /// q: FILE_SFIO_VOLUME_INFORMATION
        SfioVolumeInformation,
        /// q: FILE_LINKS_INFORMATION
        HardLinkInformation,
        /// q: FILE_PROCESS_IDS_USING_FILE_INFORMATION
        ProcessIdsUsingFileInformation,
        /// q: FILE_NAME_INFORMATION
        NormalizedNameInformation,
        /// q: FILE_NETWORK_PHYSICAL_NAME_INFORMATION
        NetworkPhysicalNameInformation,
        /// q: FILE_ID_GLOBAL_TX_DIR_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex]) // since WIN7 // 50
        IdGlobalTxDirectoryInformation,
        /// q: FILE_IS_REMOTE_DEVICE_INFORMATION
        IsRemoteDeviceInformation,
        /// q:
        UnusedInformation,
        /// q: FILE_NUMA_NODE_INFORMATION
        NumaNodeInformation,
        /// q: FILE_STANDARD_LINK_INFORMATION
        StandardLinkInformation,
        /// q: FILE_REMOTE_PROTOCOL_INFORMATION
        RemoteProtocolInformation,
        /// s: FILE_RENAME_INFORMATION // (kernel-mode only) // since WIN8
        RenameInformationBypassAccessCheck,
        /// s: FILE_LINK_INFORMATION // (kernel-mode only)
        LinkInformationBypassAccessCheck,
        /// q: FILE_VOLUME_NAME_INFORMATION
        VolumeNameInformation,
        /// q: FILE_ID_INFORMATION
        IdInformation,
        /// q: FILE_ID_EXTD_DIR_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex]) // 60
        IdExtdDirectoryInformation,
        /// s: FILE_COMPLETION_INFORMATION // since WINBLUE
        ReplaceCompletionInformation,
        /// q: FILE_LINK_ENTRY_FULL_ID_INFORMATION // FILE_LINKS_FULL_ID_INFORMATION
        HardLinkFullIdInformation,
        /// q: FILE_ID_EXTD_BOTH_DIR_INFORMATION (requires FILE_LIST_DIRECTORY) (NtQueryDirectoryFile[Ex]) // since THRESHOLD
        IdExtdBothDirectoryInformation,
        /// s: FILE_DISPOSITION_INFO_EX (requires DELETE) // since REDSTONE
        DispositionInformationEx,
        /// s: FILE_RENAME_INFORMATION_EX
        RenameInformationEx,
        /// s: FILE_RENAME_INFORMATION_EX // (kernel-mode only)
        RenameInformationExBypassAccessCheck,
        /// qs: FILE_DESIRED_STORAGE_CLASS_INFORMATION // since REDSTONE2
        DesiredStorageClassInformation,
        /// q: FILE_STAT_INFORMATION
        StatInformation,
        /// s: FILE_MEMORY_PARTITION_INFORMATION // since REDSTONE3
        MemoryPartitionInformation,
        /// q: FILE_STAT_LX_INFORMATION (requires FILE_READ_ATTRIBUTES and FILE_READ_EA) // since REDSTONE4 // 70
        StatLxInformation,
        /// qs: FILE_CASE_SENSITIVE_INFORMATION
        CaseSensitiveInformation,
        /// s: FILE_LINK_INFORMATION_EX // since REDSTONE5
        LinkInformationEx,
        /// s: FILE_LINK_INFORMATION_EX // (kernel-mode only)
        LinkInformationExBypassAccessCheck,
        /// qs: FILE_STORAGE_RESERVE_ID_INFORMATION
        StorageReserveIdInformation,
        /// qs: FILE_CASE_SENSITIVE_INFORMATION
        CaseSensitiveInformationForceAccessCheck,
        /// qs: FILE_KNOWN_FOLDER_INFORMATION // since WIN11
        KnownFolderInformation,
        /// qs: FILE_STAT_BASIC_INFORMATION // since 23H2
        StatBasicInformation,
        /// q: FILE_ID_64_EXTD_DIR_INFORMATION
        Id64ExtdDirectoryInformation,
        /// q: FILE_ID_64_EXTD_BOTH_DIR_INFORMATION
        Id64ExtdBothDirectoryInformation,
        /// q: FILE_ID_ALL_EXTD_DIR_INFORMATION
        IdAllExtdDirectoryInformation,
        /// q: FILE_ID_ALL_EXTD_BOTH_DIR_INFORMATION
        IdAllExtdBothDirectoryInformation,
        /// q: FILE_STREAM_RESERVATION_INFORMATION // since 24H2
        StreamReservationInformation,
        /// qs: MUP_PROVIDER_INFORMATION
        MupProviderInfo,
    };
    /// This must stay in sync with win32.FILE.FLAGS_AND_ATTRIBUTES.
    pub const ATTRIBUTES = packed struct(ULONG) {
        READONLY: bool = false,
        HIDDEN: bool = false,
        SYSTEM: bool = false,
        __reserved0__: u1 = 0,
        DIRECTORY: bool = false,
        ARCHIVE: bool = false,
        DEVICE: bool = false,
        NORMAL: bool = false,
        TEMPORARY: bool = false,
        SPARSE_FILE: bool = false,
        REPARSE_POINT: bool = false,
        COMPRESSED: bool = false,
        OFFLINE: bool = false,
        NOT_CONTENT_INDEXED: bool = false,
        ENCRYPTED: bool = false,
        INTEGRITY_STREAM: bool = false,
        VIRTUAL: bool = false,
        NO_SCRUB_DATA: bool = false,
        RECALL_ON_OPEN: bool = false,
        PINNED: bool = false,
        UNPINNED: bool = false,
        __reserved1__: u1 = 0,
        RECALL_ON_DATA_ACCESS: bool = false,
        __reserved2__: u6 = 0,
        STRICTLY_SEQUENTIAL: bool = false,
        __reserved3__: u2 = 0,

        pub const EA = @This(){ .RECALL_ON_OPEN = true };

        pub const default = @This(){ .NORMAL = true };
    };

    pub const BASIC_INFORMATION = extern struct {
        creation_time: LARGE_INTEGER,
        last_access_time: LARGE_INTEGER,
        last_write_time: LARGE_INTEGER,
        change_time: LARGE_INTEGER,
        file_attributes: ATTRIBUTES,
    };

    pub const SHARE = packed struct(DWORD) {
        READ: bool = false,
        WRITE: bool = false,
        DELETE: bool = false,
        __reserved__: @Int(.unsigned, @bitSizeOf(DWORD) - 3) = 0,
    };

    pub const MODE = packed struct(ULONG) {
        DIRECTORY_FILE: bool = false,
        WRITE_THROUGH: bool = false,
        SEQUENTIAL_ONLY: bool = false,
        NO_INTERMEDIATE_BUFFERING: bool = false,
        SYNCHRONOUS_IO_ALERT: bool = false,
        SYNCHRONOUS_IO_NONALERT: bool = false,
        NON_DIRECTORY_FILE: bool = false,
        CREATE_TREE_CONNECTION: bool = false,
        COMPLETE_IF_OPLOCKED: bool = false,
        NO_EA_KNOWLEDGE: bool = false,
        OPEN_REMOTE_INSTANCE: bool = false,
        RANDOM_ACCESS: bool = false,
        DELETE_ON_CLOSE: bool = false,
        OPEN_BY_FILE_ID: bool = false,
        OPEN_FOR_BACKUP_INTENT: bool = false,
        NO_COMPRESSION: bool = false,
        OPEN_REQUIRING_OPLOCK: bool = false,
        DISALLOW_EXCLUSIVE: bool = false,
        SESSION_AWARE: bool = false,
        __reserved0__: u1 = 0,
        RESERVE_OPFILTER: bool = false,
        OPEN_REPARSE_POINT: bool = false,
        OPEN_NO_RECALL: bool = false,
        OPEN_FOR_FREE_SPACE_QUERY: bool = false,
        __reserved1__: u8 = 0,
    };
};

pub const KERNEL_USER_TIMES = extern struct {
    create_time: LARGE_INTEGER,
    exit_time: LARGE_INTEGER,
    kernel_time: LARGE_INTEGER,
    user_time: LARGE_INTEGER,
};

pub const UNICODE_STRING = extern struct {
    /// !! In bytes !!
    length: USHORT,
    /// !! In bytes !!
    maximum_length: USHORT,
    buffer: PWSTR,

    pub fn init(wide_str: [:0]u16) UNICODE_STRING {
        return .{
            .length = @intCast(wide_str.len * @sizeOf(u16)),
            .maximum_length = @intCast((wide_str.len + 1) * @sizeOf(u16)),
            .buffer = wide_str.ptr,
        };
    }

    pub fn slice(this: *const UNICODE_STRING) [:0]u16 {
        return this.buffer[0 .. this.length / @sizeOf(u16) :0];
    }
};

pub const RTL_RELATIVE_NAME_U = extern struct {
    relative_name: UNICODE_STRING,
    containing_directory: HANDLE,
    cur_dir_ref: *RTLP_CURDIR_REF,
};

pub const RTLP_CURDIR_REF = extern struct {
    reference_count: LONG,
    directory_handle: HANDLE,
};

pub const OVERLAPPED = extern struct {
    internal: *ULONG,
    internal_high: *ULONG,

    dummy_union: extern union {
        dummy_struct: extern struct {
            offset: DWORD,
            offset_high: DWORD,
        },
        pointer: PVOID,
    },

    event: HANDLE,
};

pub const IO_STATUS_BLOCK = extern struct {
    u: extern union {
        status: NTSTATUS,
        pointer: ?PVOID,
    },
    information: ULONG_PTR,
};

pub const SECURITY_ATTRIBUTES = extern struct {
    length: DWORD = @sizeOf(@This()),
    security_descriptor: LPVOID,
    inherit_handle: BOOL,
};

pub const ACCESS_MASK = packed struct(DWORD) {
    specific: packed union(u16) {
        FILE: ACCESS_MASK.FILE,
        // TODO: KEY_*, PROCESS_*, THREAD_*
    } = .{ .FILE = .{} },

    DELETE: bool = false,
    READ_CONTROL: bool = false,
    WRITE_DAC: bool = false,
    WRITE_OWNER: bool = false,
    SYNCHRONIZE: bool = false,
    __reserved0__: u3 = 0,

    SYSTEM_SECURITY: bool = false,
    MAXIMUM_ALLOWED: bool = false,
    __reserved1__: u2 = 0,
    GENERIC_ALL: bool = false,
    GENERIC_EXECUTE: bool = false,
    GENERIC_WRITE: bool = false,
    GENERIC_READ: bool = false,

    pub const FILE = packed struct(u16) {
        READ_DATA: bool = false,
        WRITE_DATA: bool = false,
        APPEND_DATA: bool = false,
        READ_EA: bool = false,
        WRITE_EA: bool = false,
        EXECUTE: bool = false,
        DELETE_CHILD: bool = false,
        READ_ATTRIBUTES: bool = false,
        WRITE_ATTRIBUTES: bool = false,
        __reserved__: u7 = 0,

        pub const LIST_DIRECTORY = @This(){ .READ_DATA = true };
        pub const ADD_FILE = @This(){ .WRITE_DATA = true };
        pub const ADD_SUBDIRECTORY = @This(){ .APPEND_DATA = true };
        pub const CREATE_PIPE_INSTANCE = @This(){ .APPEND_DATA = true };
        pub const TRAVERSE = @This(){ .EXECUTE = true };
    };

    pub const SPECIFIC_RIGHTS_ALL: ACCESS_MASK = @bitCast(@as(DWORD, 0xFFFF));

    pub const STANDARD_RIGHTS_REQUIRED = ACCESS_MASK{ .DELETE = true, .READ_CONTROL = true, .WRITE_DAC = true, .WRITE_OWNER = true };
    pub const STANDARD_RIGHTS_READ = ACCESS_MASK{ .READ_CONTROL = true };
    pub const STANDARD_RIGHTS_WRITE = ACCESS_MASK{ .READ_CONTROL = true };
    pub const STANDARD_RIGHTS_EXECUTE = ACCESS_MASK{ .READ_CONTROL = true };
    pub const STANDARD_RIGHTS_ALL = ACCESS_MASK{ .DELETE = true, .READ_CONTROL = true, .WRITE_DAC = true, .WRITE_OWNER = true, .SYNCHRONIZE = true };
};

pub const FILETIME = extern union {
    u: extern struct {
        low: DWORD = 0,
        high: DWORD = 0,
    },

    // 100ns ticks
    ticks: u64 align(@alignOf(DWORD)),
};

pub extern "ntdll" fn NtQueryAttributesFile(object_attributes: *const OBJECT_ATTRIBUTES, file_info_out: *FILE.BASIC_INFORMATION) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtQueryInformationProcess(process_handle: HANDLE, process_info_class: PROCESS.INFOCLASS, process_info: *anyopaque, process_info_len: ULONG, return_len: *ULONG) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtQueryInformationThread(thread_handle: HANDLE, thread_info_class: THREAD.INFOCLASS, thread_info: *anyopaque, thread_info_len: ULONG, return_len: *ULONG) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtOpenFile(out_handle: *HANDLE, desired_access: ACCESS_MASK, object_attributes: *const OBJECT_ATTRIBUTES, out_io_status_block: *IO_STATUS_BLOCK, share_access: FILE.SHARE, open_options: FILE.MODE) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtClose(handle: HANDLE) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn NtQueryInformationFile(handle: HANDLE, out_io_status_block: *IO_STATUS_BLOCK, out_file_info: PVOID, file_info_len: ULONG, file_info_class: FILE.INFOCLASS) callconv(.winapi) NTSTATUS;

pub extern "ntdll" fn RtlDosPathNameToNtPathName_U_WithStatus(dos_file_name: PCWSTR, nt_file_name_out: *UNICODE_STRING, file_part: ?PWSTR, relative_name: ?*RTL_RELATIVE_NAME_U) callconv(.winapi) NTSTATUS;
pub extern "ntdll" fn RtlFreeUnicodeString(unicode_string: *UNICODE_STRING) callconv(.winapi) void;
/// Returned length is in bytes!
pub extern "ntdll" fn RtlGetFullPathName_U(file_name: PCWSTR, buffer_length_bytes: ULONG, out_buffer: PWSTR, out_file_part: ?PWSTR) callconv(.winapi) ULONG;
pub extern "ntdll" fn RtlGetSystemTimePrecise() callconv(.winapi) ULONGLONG;
pub extern "ntdll" fn RtlIsDosDeviceName_U(dos_file_name: PCWSTR) callconv(.winapi) ULONG;
pub extern "ntdll" fn RtlQueryPerformanceCounter(perf_count: *LARGE_INTEGER) callconv(.winapi) LOGICAL;
pub extern "ntdll" fn RtlQueryPerformanceFrequency(freq: *LARGE_INTEGER) callconv(.winapi) LOGICAL;
