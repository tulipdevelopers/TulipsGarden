pragma solidity ^0.5.16;

import "./contracts/math/Math.sol";
import "./TulipToken.sol";

import "./contracts/math/SafeMath.sol";
import "./contracts/token/ERC20/ERC20Detailed.sol";
import "./contracts/token/ERC20/SafeERC20.sol";
import "./contracts/ownership/Ownable.sol";
import "./contracts/utils/ReentrancyGuard.sol";

contract GardenContract is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for TulipToken;
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */
  
  uint256 private _epochBlockStart;

  uint256 private _epochRedTulipStart;

  uint8 private _pinkTulipDivider;

  uint256 private _decimalConverter = 10**9;

  struct  tulipToken{
      TulipToken token;
      uint256 totalSupply;
      mapping(address => uint256)  balances;
      mapping(address => uint256)  periodFinish;
  }

  tulipToken[3] private _tulipToken;

  struct externalToken{
      IERC20 token;
      uint256 rewardsDuration;
      uint256 rewardsMultiplier;
      string rewardsMultiplierType;
      uint256 totalSupply;
      address tokenAddress;
      mapping(address => uint256)  balances;
      mapping(address => uint256)  periodFinish;
  }

  externalToken[] private _externalToken;

  /* ========== CONSTRUCTOR ========== */

  constructor(address _seedToken, address _basicTulipToken, address _advTulipToken) public Ownable() {
    
    _tulipToken[0].token = TulipToken(_seedToken);
    _tulipToken[1].token = TulipToken(_basicTulipToken);
    _tulipToken[2].token = TulipToken(_advTulipToken);
    
    _pinkTulipDivider = 100;
    _epochBlockStart = 1600610400;
    _epochRedTulipStart = _epochBlockStart;
  }

  /* ========== VIEWS ========== */

      /* ========== internal ========== */

  function totalSupply(string calldata name) external view returns (uint256) {
    uint8 i = tulipType(name);
    return _tulipToken[i].totalSupply;
  }

  function durationRemaining(address account, string calldata name) external view returns (uint256) {
    uint8 i = tulipType(name);
    return _tulipToken[i].periodFinish[account].sub(now);
  }

  function balanceOf(address account, string calldata name) external view returns (uint256)
  {
    uint8 i = tulipType(name);
    return _tulipToken[i].balances[account];
  }

      /* ========== external ========== */

    function totalExternalSupply(address extToken) external view returns (uint256) {
      uint8 i = externalTokenIndex(extToken);
      return _externalToken[i].totalSupply;
    }

    function externalDurationRemaining(address account, address extToken) external view returns (uint256) {
      uint8 i = externalTokenIndex(extToken);
      return _externalToken[i].periodFinish[account].sub(now);
    }

    function externalBalanceOf(address account, address extToken) external view returns (uint256)
    {
      uint8 i = externalTokenIndex(extToken);
      return  _externalToken[i].balances[account];
    } 

  /* ========== MUTATIVE FUNCTIONS ========== */

      /* ========== internal garden ========== */
  function plant(uint256 amount, string calldata name) external nonReentrant {    
    require(now > _epochBlockStart, "The garden is being set up!");

    uint8 i = tulipType(name);

    require(i < 99, "Not a valid tulip name");
    
    require(amount >= 1, "Cannot stake less than 1");

    if(i == 1){
      uint256 modulo = amount % 100;
      require(modulo == 0, "If planting a pink tulip, has to be multiple of 100");
    }

    require(_tulipToken[i].balances[msg.sender] == 0 && (_tulipToken[i].periodFinish[msg.sender] == 0 || now > _tulipToken[i].periodFinish[msg.sender]), 
    "You must withdraw the previous crop before planting more!");

    _tulipToken[i].token.safeTransferFrom(msg.sender, address(this), amount.mul(_decimalConverter));

    _tulipToken[i].totalSupply = _tulipToken[i].totalSupply.add(amount);

    _tulipToken[i].balances[msg.sender] = _tulipToken[i].balances[msg.sender].add(amount);

    setTimeStamp(i);

    emit Staked(msg.sender, amount);
  }

  
  function withdraw(string memory name) public nonReentrant {
    uint8 i = tulipType(name);

    require(i < 99, "Not a valid tulip name");

    require(_tulipToken[i].balances[msg.sender] > 0, "Cannot withdraw 0");

    _tulipToken[i].token.safeTransfer(msg.sender, _tulipToken[i].balances[msg.sender].mul(_decimalConverter));

    emit Withdrawn(msg.sender,_tulipToken[i].balances[msg.sender]);

    zeroHoldings(i);
  }


  function harvest(string memory name) public nonReentrant {
    uint8 i = tulipType(name);

    require(i < 99, "Not a valid tulip name");
    
    require(_tulipToken[i].balances[msg.sender] > 0, "Cannot harvest 0");
    
    require(now > _tulipToken[i].periodFinish[msg.sender], "Cannot harvest until the flowers have bloomed!");

    uint256 tempAmount;

    if (i == 2) {
      tempAmount = setRedTulipRewardAmount();
      _tulipToken[0].token.contractMint(msg.sender, tempAmount.mul(_decimalConverter));
      _tulipToken[i].periodFinish[msg.sender] = now.add(7 days);
    } 
    else {
      _tulipToken[i].token.contractBurn(address(this), _tulipToken[i].balances[msg.sender].mul(_decimalConverter));
      if(i == 1){
        tempAmount = _tulipToken[i].balances[msg.sender].div(_pinkTulipDivider);
      }
      else{
        tempAmount = _tulipToken[i].balances[msg.sender];
      }
      
      _tulipToken[i + 1].token.contractMint(msg.sender, tempAmount.mul(_decimalConverter));

      zeroHoldings(i);
    }
    emit RewardPaid(msg.sender, tempAmount);
  }

      /* ========== external garden ========== */

  function externalPlant(uint256 amount, address tokenAddress) external nonReentrant {    
    require(now > _epochBlockStart, "The garden is being set up!");

    uint8 i = externalTokenIndex(tokenAddress);

    require(i < 99, "Not a valid token address");

    require(amount > 0, "Cannot stake 0");

    require(_externalToken[i].balances[msg.sender] == 0 && (_externalToken[i].periodFinish[msg.sender] == 0 || now > _externalToken[i].periodFinish[msg.sender]), 
    "You must withdraw the previous stake before planting more!");

    _externalToken[i].token.safeTransferFrom(msg.sender, address(this), amount);

    _externalToken[i].totalSupply = _externalToken[i].totalSupply.add(amount);

    _externalToken[i].balances[msg.sender] = _externalToken[i].balances[msg.sender].add(amount);

    _externalToken[i].periodFinish[msg.sender] = now.add(_externalToken[i].rewardsDuration);

    emit Staked(msg.sender, amount);
  }

  
  function externalWithdraw(address tokenAddress) public nonReentrant {
    uint8 i = externalTokenIndex(tokenAddress);

    require(i < 99, "Not a valid token address");

    require(_externalToken[i].totalSupply > 0, "Cannot withdraw 0");

    _externalToken[i].token.safeTransfer(msg.sender, _externalToken[i].balances[msg.sender]);

    emit Withdrawn(msg.sender, _externalToken[i].balances[msg.sender]);

     _externalToken[i].totalSupply = _externalToken[i].totalSupply - _externalToken[i].balances[msg.sender];
     _externalToken[i].balances[msg.sender] = 0;
     _externalToken[i].periodFinish[msg.sender] = 0;
  }


  function externalHarvest(address tokenAddress) public nonReentrant {
    uint8 i = externalTokenIndex(tokenAddress);

    require(i < 99, "Not a valid token address");

    require(_externalToken[i].totalSupply > 0, "Cannot harvest 0");

    require(now > _externalToken[i].periodFinish[msg.sender], "Cannot harvest until the flowers have bloomed!");

    if(keccak256(abi.encodePacked(_externalToken[i].rewardsMultiplier)) == keccak256(abi.encodePacked("div"))){
      _tulipToken[0].token.contractMint(msg.sender, _externalToken[i].totalSupply.div(_externalToken[i].rewardsMultiplier));
    }else{
      _tulipToken[0].token.contractMint(msg.sender, _externalToken[i].totalSupply.mul(_externalToken[i].rewardsMultiplier));
    }

    _externalToken[i].periodFinish[msg.sender] = now.add(_externalToken[i].rewardsDuration);
    
    emit RewardPaid(msg.sender, _externalToken[i].totalSupply.mul(_externalToken[i].rewardsMultiplier));
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

      /* ========== internal functions ========== */

  function addTokenOwner(address _token, address _newOwner) external onlyOwner
  {
    require(now > _epochBlockStart.add(30 days), "The admin functions are timelocked");

    TulipToken tempToken = TulipToken(_token);
    tempToken.addOwner(_newOwner);
  }

  function renounceTokenOwner(address _token) external onlyOwner
  {
    require(now > _epochBlockStart.add(30 days), "The admin functions are timelocked");

    TulipToken tempToken = TulipToken(_token);
    tempToken.renounceOwner();
  }

  function changeOwner(address _newOwner) external onlyOwner {
    transferOwnership(_newOwner);
  }

      /* ========== external functions ========== */

  function changeExternalTokenDuration(address _tokenAddress, uint256 _newDuration) external onlyOwner {
    uint8 i = externalTokenIndex(_tokenAddress);

    _externalToken[i].rewardsDuration = _newDuration;
  }


  function changeExternalTokenMultiplier(address _tokenAddress, uint256 _newMultiplier, string calldata _multType) external onlyOwner {
    uint8 i = externalTokenIndex(_tokenAddress);

    _externalToken[i].rewardsMultiplierType = _multType;
    _externalToken[i].rewardsMultiplier = _newMultiplier;
  }


  function addExternalToken(address _tokenAddress, uint256 _duration, uint256 _multiplier, string calldata _multiplierType ) external onlyOwner {
    require(keccak256(abi.encodePacked(_multiplierType)) == keccak256(abi.encodePacked("div"))|| keccak256(abi.encodePacked(_multiplierType)) == keccak256(abi.encodePacked("mul")), "Please enter a valid multiplier type");
   
    for(uint8 i = 0; i < _externalToken.length; i++){
      if(_externalToken[i].tokenAddress == _tokenAddress){
        require(_externalToken[i].tokenAddress != _tokenAddress, "This token has already been added!");
      }
    }

    _externalToken.push(externalToken(
      IERC20(_tokenAddress),
      _duration,
      _multiplier,
      _multiplierType,
      0,
       _tokenAddress
    ));
  }


  /* ========== HELPER FUNCTIONS ========== */

  function tulipType(string memory name) internal pure returns (uint8) {
    if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("sTLP"))) {
      return 0;
    }
    if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("pTLP"))) {
      return 1;
    }
    if (keccak256(abi.encodePacked(name)) == keccak256(abi.encodePacked("rTLP"))) {
      return 2;
    } else {
      return 99;
    }
  }


  function externalTokenIndex(address tokenAddress) internal view returns(uint8){
    for (uint8 i = 0; i < _externalToken.length; i++){
      if(_externalToken[i].tokenAddress == tokenAddress){
        return i;
      }
    }
  }


  function setTimeStamp(uint8 i) internal{
    if (i == 0) {
      setRewardDurationSeeds();
    }
    if (i == 1) {
      setRewardDurationTulip();
    }
    if (i == 2) {
      _tulipToken[i].periodFinish[msg.sender] = now.add(7 days);
    }
  }


  function zeroHoldings(uint8 i) internal{
    _tulipToken[i].totalSupply = _tulipToken[i].totalSupply - _tulipToken[i].balances[msg.sender];
    _tulipToken[i].balances[msg.sender] = 0;
    _tulipToken[i].periodFinish[msg.sender] = 0;
  }

  /* ========== REAL FUNCTIONS ========== */
  
  function setRewardDurationSeeds() internal returns (bool) {
    uint256 timeSinceEpoch = ((now - _epochBlockStart) / 60 / 60 / 24 / 30) + 1;

    if (timeSinceEpoch >= 7) {
      _tulipToken[0].periodFinish[msg.sender] = now.add(7 days);
      return true;
    } else {
      _tulipToken[0].periodFinish[msg.sender] = now.add(
        timeSinceEpoch.mul(1 days)
      );
      return true;
    }
  }


  function setRewardDurationTulip() internal returns (bool) {
    uint256 timeSinceEpoch = ((now - _epochBlockStart) / 60 / 60 / 24) + 1;

    if (timeSinceEpoch <= 2) {
      _tulipToken[1].periodFinish[msg.sender] = now.add(2 days);
      return true;
    }
    if (timeSinceEpoch > 2 && timeSinceEpoch <= 7) {
      _tulipToken[1].periodFinish[msg.sender] = now.add(3 days);
      return true;
    }
    if (timeSinceEpoch > 7 && timeSinceEpoch <= 14) {
      _tulipToken[1].periodFinish[msg.sender] = now.add(7 days);
      return true;
    }
    if (timeSinceEpoch > 14) {
      uint256 tempInt = (timeSinceEpoch - 15 days) / 30;

      if (tempInt >= 7) {
        _tulipToken[1].periodFinish[msg.sender] = now.add(30 days);
        return true;
      } else {
        _tulipToken[1].periodFinish[msg.sender] = now.add(
          14 days + (tempInt.mul(2 days))
        );
        return true;
      }
    }
  }


  function setRedTulipRewardAmount() internal view returns (uint256) {
    uint256 timeSinceEpoch = (now - _tulipToken[2].periodFinish[msg.sender].sub(7 days)) / 60 / 60 / 24;
    uint256 amountWeeks = timeSinceEpoch.div(7);
    uint256 newtime = now;
    uint256 value = 0;

    for (uint256 i = amountWeeks; i != 0; i--) {
      uint256 tempTime = newtime.sub(i.mul(7 days));

      if (tempTime > _epochRedTulipStart && tempTime <= _epochRedTulipStart.add(7 days)) {
        value = value.add(50);
      }
      if (tempTime > _epochRedTulipStart.add(7 days) && tempTime <= _epochRedTulipStart.add(21 days)) {
        value = value.add(25);
      }
      if (tempTime > _epochRedTulipStart.add(21 days)) {
        value = value.add(10);
      }
    }
    return value * _tulipToken[2].balances[msg.sender];
  }

  /* ========== EVENTS ========== */
  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);
  event RewardPaid(address indexed user, uint256 reward);
}