-- Adminer 4.8.1 MySQL 8.0.33 dump
USE electronic_db;
SET NAMES utf8;
SET time_zone = '+00:00';
SET foreign_key_checks = 0;
SET sql_mode = 'NO_AUTO_VALUE_ON_ZERO';

USE `electronic_db`;

DELIMITER ;;

DROP PROCEDURE IF EXISTS `deleteAllTokenByUserId`;;
CREATE PROCEDURE `deleteAllTokenByUserId`(IN userId INT)
BEGIN
          DECLARE count_account INT;
          DECLARE number_deleted INT;
          SELECT COUNT(*) INTO count_account FROM refreshtoken WHERE user_id = userId;
          SET number_deleted = count_account-2;
          IF (count_account > 2) THEN
          delete from refreshtoken where user_id = userId ORDER BY id limit number_deleted;
          END IF;
END;;

DROP PROCEDURE IF EXISTS `order_history`;;
CREATE PROCEDURE `order_history`(in id_order_status int, in user_id int,`limit` INTEGER,in `offset` INTEGER)
BEGIN
			IF EXISTS (SELECT * FROM order_status WHERE order_status.id = id_order_status) THEN
				SELECT * FROM orders WHERE orders.`status` = id_order_status and orders.user_id = user_id LIMIT `limit` OFFSET `offset`;
			ELSE
				SELECT * FROM orders WHERE orders.user_id = user_id LIMIT `limit` OFFSET `offset`;
			END IF;
	END;;

DROP PROCEDURE IF EXISTS `sp_checkCurrentInvetory`;;
CREATE PROCEDURE `sp_checkCurrentInvetory`(in variant_id int, reQty int, out checked int)
begin
	set  checked = 404;
	if exists (select * from product_variant v where v.id = variant_id ) 
    then
		set @inventory := -1;
        select quantity into @inventory from product_variant v where v.id = variant_id;
        select case 
				when @inventory = 0 and reQty = 0 then 1
                when @inventory = 0 then 0
                when reQty = 0 and @inventory > 0 then 202
                when @inventory >=  reQty then 1
                when @inventory <  reQty then (@inventory -  reQty)
                end into checked; 
		end if;
end;;

DROP PROCEDURE IF EXISTS `sp_reduceVariantQtyInOrderByOrderId`;;
CREATE PROCEDURE `sp_reduceVariantQtyInOrderByOrderId`(In orderId int, out updated bool)
begin
if exists (select * from orders o join order_detail od on od.order_id = o.id where o.id = orderId)
then
UPDATE  product_variant v
INNER JOIN  order_detail od
        ON v.id = od.product_variant_id and od.order_id = orderId
SET v.quantity = case when v.quantity = 0 then v.quantity 
						when v.quantity > 0 then v.quantity  - od.quantity
                    end;
set updated = true;
else set updated = false;
end if;
end;;

DROP PROCEDURE IF EXISTS `sp_sumTotalInCart`;;
CREATE PROCEDURE `sp_sumTotalInCart`(In cartId int,
    out updated bool)
BEGIN
IF exists (SELECT * FROM cart c join cart_detail d on d.cart_id = c.id WHERE c.id = cartId) THEN
BEGIN
     DECLARE total DOUBLE DEFAULT 0.0;
		set total = (select sum(d.quantity * v.price) 
		from cart_detail d 
		join cart c on d.cart_id = c.id
		join product_variant v on v.id = d.product_variant_id
		where c.id = cartId);        
        update cart set price_sum = total where id = cartId; 
        set updated = true;
END;
ELSE
BEGIN
	IF (select id from cart c where c.id = cartId) then
    begin
     update cart set price_sum = 0.0 where id = cartId; 
     set updated = true;
    end ;
    else
    begin
	set updated = false;
    end;
    end if;
END;
END IF;
END;;

DROP PROCEDURE IF EXISTS `sp_updateCartByInventory`;;
CREATE PROCEDURE `sp_updateCartByInventory`(IN cartId int, OUT ischanged bool)
BEGIN
	DECLARE finished INTEGER DEFAULT 0;
	DECLARE cartDetailId int DEFAULT 0;
	DECLARE cartQty int DEFAULT 0;
	DECLARE flag int default 404;

	-- declare cursor for cart-detail id that has cart_id match param cartId
	DEClARE userCart 
		CURSOR FOR 
			SELECT cd.id  FROM cart c JOIN cart_detail cd on c.id = cd.cart_id where c.id = cartId ;

	-- declare NOT FOUND handler
	DECLARE CONTINUE HANDLER 
        FOR NOT FOUND SET finished = 1;

	OPEN userCart;

	updatedCart: LOOP
		FETCH userCart INTO cartDetailId;
		IF finished = 1 THEN 
			LEAVE updatedCart;
		END IF;
		-- call update cart
        Call sp_updateCartDetailByInventory(cartId, cartDetailId, flag);
        if(flag <= 0 or flag = 202) then begin set ischanged = true; end ;
        end if;
	END LOOP updatedCart;
	CLOSE userCart;
	select case 
		when ischanged is null then false
        when ischanged = false then false
        when ischanged = true then true
        end into ischanged;
END;;

DROP PROCEDURE IF EXISTS `sp_updateCartByVariantStatus`;;
CREATE PROCEDURE `sp_updateCartByVariantStatus`(in cartId int, out isRemoved bool)
begin
	DECLARE finished INTEGER DEFAULT 0;
	DECLARE cartDetailId int DEFAULT 0;
	DECLARE flag int default 404;

	-- declare cursor for cart_detail by cart_id
	DEClARE userCart 
		CURSOR FOR 
			SELECT cd.id  FROM cart c JOIN cart_detail cd on c.id = cd.cart_id where c.id = cartId ;

	-- declare NOT FOUND handler
	DECLARE CONTINUE HANDLER 
        FOR NOT FOUND SET finished = 1;

	OPEN userCart;

	updatedCart: LOOP
		FETCH userCart INTO cartDetailId;
		IF finished = 1 THEN 
			LEAVE updatedCart;
		END IF;
		-- class update cart
        Call sp_updateCartDetailByVariantStatus(cartId, cartDetailId, flag);
        if(flag = true) then begin set  isRemoved = true; end ;
        end if;
	END LOOP updatedCart;
	CLOSE userCart;
	select case 
		when  isRemoved is null then false
        when  isRemoved = false then false
        when  isRemoved = true then true
        end into  isRemoved;
end;;

DROP PROCEDURE IF EXISTS `sp_updateCartDetailByInventory`;;
CREATE PROCEDURE `sp_updateCartDetailByInventory`(In cartId int, cartDetailId int,out updated int)
begin
if exists (select * from cart c join cart_detail cd on c.id = cd.cart_id where c.id = cartId)
then begin
	set @checked :=404;
	set @variantId := 0;
    set @updatedSum := false;
    select product_variant_id into @variantId from cart_detail where id = cartDetailId;
	set @reQty := 0;
    select quantity into @reQty from cart_detail where id = cartDetailId;
	call sp_checkCurrentInvetory(@variantId, @reQty, @checked);
		if(@checked != 404 and (@checked = 0 or @checked <= -5)) 
			then begin
				update cart_detail set quantity = 0 where id = cartDetailId;
				-- delete from cart_detail where id = cartDetailId;
                call sp_sumTotalInCart(cartId,@updatedSum);
                set updated = @checked;
			end;
		elseif(@checked != 404 and @checked < 0) 
			then begin
			update cart_detail set quantity = quantity + @checked where id = cartDetailId;
             call sp_sumTotalInCart(cartId,@updatedSum);
            set updated = @checked;
			end;
        elseif(@checked  = 202) 
        then begin
			update cart_detail set quantity = 1 where id = cartDetailId;
             call sp_sumTotalInCart(cartId,@updatedSum);
            set updated = @checked;
        end;
		else begin
				set updated = @checked;
			end;
       end if;  
end;       
else begin set updated = 404; end;
end if;
end;;

DROP PROCEDURE IF EXISTS `sp_updateCartDetailByVariantStatus`;;
CREATE PROCEDURE `sp_updateCartDetailByVariantStatus`(in cartId int,cartDetailId int, out isRemoved bool)
begin
    if exists (select * from cart c join cart_detail cd on c.id = cd.cart_id where c.id = cartId and cd.id = cartDetailId) 
    then begin
		set @v_status = true;
        set @variant_id = 0;
        set @sum = true;
        select v.id into @variant_id from product_variant v join cart_detail d on d.product_variant_id = v.id where d.id = cartDetailId;
		select v.status into @v_status from product_variant v where v.id = @variant_id;
        if(@v_status = false) then
        begin
			delete from cart_detail where id = cartDetailId;
            set isRemoved = true;
            call sp_sumTotalInCart(cartId, @sum);
        end;
        else begin  set isRemoved = false; end;
        end if;
    end;
    end if;
	select case 
		when isRemoved  is null then false
        when isRemoved  = false then false
        when isRemoved  = true then true
        end into isRemoved ;
end;;

DELIMITER ;

SET NAMES utf8mb4;

DROP TABLE IF EXISTS `account`;
CREATE TABLE `account` (
  `unique_id` int NOT NULL AUTO_INCREMENT,
  `username` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `password` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `create_date` datetime DEFAULT NULL,
  `update_date` datetime DEFAULT NULL,
  `active` bit(1) DEFAULT NULL,
  `last_access` datetime DEFAULT NULL,
  `user_id` int DEFAULT NULL,
  PRIMARY KEY (`unique_id`) USING BTREE,
  UNIQUE KEY `user_id` (`user_id`) USING BTREE,
  UNIQUE KEY `username` (`username`) USING BTREE,
  KEY `fk_account_user_1` (`unique_id`) USING BTREE,
  CONSTRAINT `fk_account_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `account` (`unique_id`, `username`, `password`, `create_date`, `update_date`, `active`, `last_access`, `user_id`) VALUES
(1,	'phu',	'$2a$10$VbGUM8Z2CjKOXbBJ9HLMg.z7vu6IusJknVjJR06DModLFTRwuYv5O',	'2023-04-08 23:12:58',	NULL,	CONV('1', 2, 10) + 0,	NULL,	1),
(14,	'nhatabc',	'$2a$10$fDVM77ls5JU5xysMPh9ubOjmKuXuuKI6zUC/3balaojIHJyGhv7f.',	NULL,	NULL,	CONV('1', 2, 10) + 0,	NULL,	25),
(15,	'long',	'$2a$09$3v/9yLYrM6t.OinpvQm.A.BlRWHD7pR/P88mT9tRkezxak6NZwt7S',	NULL,	NULL,	CONV('1', 2, 10) + 0,	NULL,	26),
(16,	'hoang',	'$2a$10$cxZlMtX5U.baKcF5q7Fw2.WJx45nhXv26HFlLYwFCeTp76YC4toyq',	NULL,	NULL,	CONV('1', 2, 10) + 0,	NULL,	37),
(17,	'hieuhoang',	'$2a$10$h1LHtDrHMZF5PBe6FNqtiu4THeoR2KsFZmQF8k2NFO75nZvOEykfy',	NULL,	NULL,	CONV('1', 2, 10) + 0,	NULL,	40),
(18,	'tainguyen',	'$2a$10$FwX4VoxMcEDH5VXAkVRHauI3.q08LUEo3UBfZnWFiEKf5F/2qx3ea',	NULL,	NULL,	CONV('1', 2, 10) + 0,	NULL,	44),
(19,	'wolade',	'$2a$10$UeJFcONX/5j2TQuRLWsfFOKgMU5tHvTctfOyKSdXIyRM0e0wWv5Ai',	NULL,	NULL,	CONV('1', 2, 10) + 0,	NULL,	45);

DELIMITER ;;

CREATE TRIGGER `a_i_account` AFTER INSERT ON `account` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'account'; 						SET @pk_d = CONCAT('<unique_id>',NEW.`unique_id`,'</unique_id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_account` AFTER UPDATE ON `account` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'account';						SET @pk_d_old = CONCAT('<unique_id>',OLD.`unique_id`,'</unique_id>');						SET @pk_d = CONCAT('<unique_id>',NEW.`unique_id`,'</unique_id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_account` AFTER DELETE ON `account` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'account';						SET @pk_d = CONCAT('<unique_id>',OLD.`unique_id`,'</unique_id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `address`;
CREATE TABLE `address` (
  `id` int NOT NULL AUTO_INCREMENT,
  `wards` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `district` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `address_line` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `province` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `postal_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `is_default` bit(1) DEFAULT NULL,
  `user_id` int DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  KEY `fk_user_address_1` (`user_id`) USING BTREE,
  CONSTRAINT `fk_user_address_1` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `address` (`id`, `wards`, `district`, `address_line`, `province`, `postal_id`, `is_default`, `user_id`) VALUES
(1,	'Phường Tân Chánh Hiệp',	'Quận 12',	'đường 12',	'Thành phố Hồ Chí Minh',	'00000000',	CONV('1', 2, 10) + 0,	1),
(2,	'Tân chánh hiệp',	'Quận 12',	'đường',	'Hồ Chí Minh',	'00000000',	CONV('1', 2, 10) + 0,	26),
(21,	'Phường 02',	'Quận 11',	'123A Nguyễn Thiện Thuật',	'Thành phố Hồ Chí Minh',	'457726',	CONV('1', 2, 10) + 0,	25),
(22,	'Xã Hưng Mỹ',	'Huyện Cái Nước',	'12/12/90 Phạm Ngũ Lão',	'Tỉnh Cà Mau',	'814771',	CONV('0', 2, 10) + 0,	25),
(25,	'Phường Duyên Hải',	'Thành phố Lào Cai',	'123',	'Tỉnh Lào Cai',	'616654',	CONV('1', 2, 10) + 0,	44),
(32,	'Phường Phạm Ngũ Lão',	'Quận 1',	'12A Đa Kao',	'Thành phố Hồ Chí Minh',	'300536',	CONV('1', 2, 10) + 0,	45),
(33,	'Phường Cống Vị',	'Quận Ba Đình',	'A3 ',	'Thành phố Hà Nội',	'547262',	CONV('1', 2, 10) + 0,	41);

DELIMITER ;;

CREATE TRIGGER `a_i_address` AFTER INSERT ON `address` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'address'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_address` AFTER UPDATE ON `address` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'address';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_address` AFTER DELETE ON `address` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'address';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `authority`;
CREATE TABLE `authority` (
  `unique_id` int NOT NULL AUTO_INCREMENT,
  `role_id` int DEFAULT NULL,
  `account_id` int DEFAULT NULL,
  PRIMARY KEY (`unique_id`) USING BTREE,
  KEY `fk_authority_account_1` (`account_id`) USING BTREE,
  KEY `fk_authority_role_1` (`role_id`) USING BTREE,
  CONSTRAINT `fk_authority_account_1` FOREIGN KEY (`account_id`) REFERENCES `account` (`unique_id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_authority_role_1` FOREIGN KEY (`role_id`) REFERENCES `role` (`unique_id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `authority` (`unique_id`, `role_id`, `account_id`) VALUES
(2,	2,	1),
(12,	2,	14),
(14,	2,	15),
(15,	2,	16),
(16,	1,	17),
(17,	1,	18),
(19,	2,	19);

DELIMITER ;;

CREATE TRIGGER `a_i_authority` AFTER INSERT ON `authority` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'authority'; 						SET @pk_d = CONCAT('<unique_id>',NEW.`unique_id`,'</unique_id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_authority` AFTER UPDATE ON `authority` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'authority';						SET @pk_d_old = CONCAT('<unique_id>',OLD.`unique_id`,'</unique_id>');						SET @pk_d = CONCAT('<unique_id>',NEW.`unique_id`,'</unique_id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_authority` AFTER DELETE ON `authority` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'authority';						SET @pk_d = CONCAT('<unique_id>',OLD.`unique_id`,'</unique_id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `brand`;
CREATE TABLE `brand` (
  `id` int NOT NULL AUTO_INCREMENT,
  `brand_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `image` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_date` datetime DEFAULT NULL,
  `updated_date` datetime DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `brand` (`id`, `brand_name`, `image`, `created_date`, `updated_date`) VALUES
(1,	'Samsung',	NULL,	NULL,	NULL),
(2,	'Apple',	NULL,	'2023-04-08 14:50:47',	NULL),
(5,	'Huawei',	NULL,	NULL,	NULL),
(77,	'OPPO',	NULL,	NULL,	NULL),
(78,	'DELL',	NULL,	NULL,	NULL),
(79,	'Sony',	NULL,	NULL,	NULL),
(82,	'Lenovo',	NULL,	NULL,	NULL);

DELIMITER ;;

CREATE TRIGGER `a_i_brand` AFTER INSERT ON `brand` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'brand'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_brand` AFTER UPDATE ON `brand` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'brand';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_brand` AFTER DELETE ON `brand` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'brand';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `cart`;
CREATE TABLE `cart` (
  `id` int NOT NULL AUTO_INCREMENT,
  `user_id` int DEFAULT NULL,
  `create_date` datetime DEFAULT NULL,
  `price_sum` double DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `user_id` (`user_id`) USING BTREE,
  KEY `fk_user_cart_1` (`user_id`) USING BTREE,
  CONSTRAINT `fk_user_cart_1` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `cart` (`id`, `user_id`, `create_date`, `price_sum`) VALUES
(1,	1,	'2023-04-09 15:51:25',	281180000),
(2,	26,	'2023-04-09 19:38:45',	0),
(6,	28,	'2023-04-10 14:41:46',	44280000),
(7,	29,	'2023-04-11 13:53:28',	45980000),
(10,	32,	'2023-04-12 16:18:27',	82990000),
(12,	25,	'2023-04-12 16:52:53',	23890000),
(13,	35,	'2023-04-14 16:02:55',	0),
(14,	36,	'2023-04-15 13:41:26',	15000000),
(15,	37,	'2023-04-15 13:43:30',	0),
(16,	38,	'2023-04-15 14:25:49',	0),
(17,	39,	'2023-04-15 14:53:46',	8790000),
(18,	40,	'2023-04-15 16:10:27',	25000000),
(19,	41,	'2023-04-16 16:35:50',	34000000),
(20,	42,	'2023-04-18 10:03:10',	0),
(21,	43,	'2023-04-19 19:19:29',	0),
(22,	44,	'2023-04-21 16:42:57',	0),
(23,	45,	'2023-04-23 18:59:42',	32380000);

DELIMITER ;;

CREATE TRIGGER `a_i_cart` AFTER INSERT ON `cart` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'cart'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_cart` AFTER UPDATE ON `cart` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cart';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_cart` AFTER DELETE ON `cart` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'cart';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `cart_detail`;
CREATE TABLE `cart_detail` (
  `id` int NOT NULL AUTO_INCREMENT,
  `cart_id` int DEFAULT NULL,
  `quantity` int DEFAULT NULL,
  `create_date` datetime DEFAULT NULL,
  `product_variant_id` int DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  KEY `fk_cart_detail_product_variant_1` (`product_variant_id`) USING BTREE,
  KEY `fk_cart_detail_cart_1` (`cart_id`) USING BTREE,
  CONSTRAINT `fk_cart_detail_cart_1` FOREIGN KEY (`cart_id`) REFERENCES `cart` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_cart_detail_product_variant_1` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variant` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `cart_detail` (`id`, `cart_id`, `quantity`, `create_date`, `product_variant_id`) VALUES
(45,	6,	1,	'2023-04-10 14:41:48',	59),
(46,	6,	1,	'2023-04-10 14:41:48',	57),
(47,	7,	2,	'2023-04-11 15:44:01',	65),
(68,	10,	1,	'2023-04-12 16:18:37',	65),
(139,	10,	4,	'2023-04-15 16:01:04',	58),
(141,	18,	1,	'2023-04-15 16:18:34',	73),
(156,	17,	1,	'2023-04-16 07:22:38',	67),
(243,	14,	1,	'2023-04-22 20:36:14',	58),
(352,	23,	1,	'2023-04-24 14:18:46',	63),
(356,	23,	1,	'2023-04-24 18:46:40',	57),
(359,	1,	3,	'2023-04-24 21:25:11',	76),
(360,	19,	1,	'2023-04-24 21:25:13',	68),
(366,	1,	5,	'2023-04-24 22:03:35',	58),
(368,	1,	5,	'2023-04-24 22:03:52',	62),
(369,	1,	5,	'2023-04-24 22:03:59',	66),
(372,	1,	1,	'2023-04-24 22:04:13',	57),
(373,	1,	1,	'2023-04-24 22:04:22',	78),
(375,	12,	0,	'2023-04-24 22:26:02',	55),
(383,	12,	1,	'2023-04-25 19:12:56',	57);

DELIMITER ;;

CREATE TRIGGER `a_i_cart_detail` AFTER INSERT ON `cart_detail` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'cart_detail'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_cart_detail` AFTER UPDATE ON `cart_detail` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cart_detail';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_cart_detail` AFTER DELETE ON `cart_detail` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cart_detail';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `category`;
CREATE TABLE `category` (
  `id` int NOT NULL AUTO_INCREMENT,
  `category_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `parent_id` int DEFAULT NULL,
  `create_date` datetime DEFAULT NULL,
  `update_date` datetime DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  KEY `fk_category_category_1` (`parent_id`) USING BTREE,
  CONSTRAINT `fk_category_category_1` FOREIGN KEY (`parent_id`) REFERENCES `category` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `category` (`id`, `category_name`, `parent_id`, `create_date`, `update_date`) VALUES
(1,	'Điện thoại',	NULL,	NULL,	'2023-04-10 15:52:22'),
(2,	'Laptop',	NULL,	'2023-04-08 14:49:06',	'2023-04-08 14:49:50'),
(3,	'PC',	NULL,	NULL,	'2023-04-10 16:55:30'),
(4,	'Iphone (IOS)',	1,	'2023-04-08 14:49:12',	NULL),
(6,	'Android',	1,	'2023-04-08 14:49:18',	NULL),
(7,	'Laptop gaming',	2,	'2023-04-08 14:49:21',	NULL),
(8,	'Laptop văn phòng',	2,	'2023-04-08 14:49:25',	NULL),
(36,	'PC văn phòng',	3,	'2023-04-10 16:56:20',	'2023-04-10 16:56:20'),
(39,	'PC Gaming',	3,	'2023-04-10 17:22:07',	'2023-04-10 17:22:07'),
(41,	'PC live stream',	3,	'2023-04-10 17:32:08',	'2023-04-10 17:32:08'),
(42,	'Tai nghe',	NULL,	'2023-04-10 18:01:45',	'2023-04-10 18:01:45'),
(45,	'Tai nghe có dây',	42,	'2023-04-24 21:33:45',	'2023-04-24 21:33:45');

DELIMITER ;;

CREATE TRIGGER `a_i_category` AFTER INSERT ON `category` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'category'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_category` AFTER UPDATE ON `category` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'category';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_category` AFTER DELETE ON `category` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'category';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `color`;
CREATE TABLE `color` (
  `id` int NOT NULL AUTO_INCREMENT,
  `color_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `color_code` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `color` (`id`, `color_name`, `color_code`) VALUES
(1,	'Màu đen',	'#000'),
(2,	'Trắng',	'#fff'),
(3,	'Xanh',	'#00ff00'),
(4,	'Đỏ',	'#ff0000'),
(5,	'Vàng',	'#'),
(6,	'Cam',	'#'),
(7,	'Xanh lá',	'#'),
(8,	'Tím',	'#'),
(9,	'Hồng',	'#'),
(10,	'Bạc',	'#');

DELIMITER ;;

CREATE TRIGGER `a_i_color` AFTER INSERT ON `color` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'color'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_color` AFTER UPDATE ON `color` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'color';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_color` AFTER DELETE ON `color` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'color';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `hibernate_sequence`;
CREATE TABLE `hibernate_sequence` (
  `next_val` int NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`next_val`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `hibernate_sequence` (`next_val`) VALUES
(1507);

DELIMITER ;;

CREATE TRIGGER `a_i_hibernate_sequence` AFTER INSERT ON `hibernate_sequence` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'hibernate_sequence'; 						SET @pk_d = CONCAT('<next_val>',NEW.`next_val`,'</next_val>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_hibernate_sequence` AFTER UPDATE ON `hibernate_sequence` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'hibernate_sequence';						SET @pk_d_old = CONCAT('<next_val>',OLD.`next_val`,'</next_val>');						SET @pk_d = CONCAT('<next_val>',NEW.`next_val`,'</next_val>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_hibernate_sequence` AFTER DELETE ON `hibernate_sequence` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'hibernate_sequence';						SET @pk_d = CONCAT('<next_val>',OLD.`next_val`,'</next_val>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `history_store`;
CREATE TABLE `history_store` (
  `timemark` timestamp NOT NULL,
  `table_name` tinytext COLLATE utf8mb3_bin NOT NULL,
  `pk_date_src` text COLLATE utf8mb3_bin NOT NULL,
  `pk_date_dest` text COLLATE utf8mb3_bin NOT NULL,
  `record_state` int NOT NULL,
  PRIMARY KEY (`table_name`(85),`pk_date_dest`(85))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin;

INSERT INTO `history_store` (`timemark`, `table_name`, `pk_date_src`, `pk_date_dest`, `record_state`) VALUES
('2023-04-23 18:59:15',	'account',	'<unique_id>19</unique_id>',	'<unique_id>19</unique_id>',	1),
('2023-04-23 15:59:14',	'address',	'<id>1</id>',	'<id>1</id>',	2),
('2023-04-22 22:37:46',	'address',	'<id>25</id>',	'<id>25</id>',	1),
('2023-04-23 22:51:27',	'address',	'<id>32</id>',	'<id>32</id>',	1),
('2023-04-24 21:22:40',	'address',	'<id>33</id>',	'<id>33</id>',	1),
('2023-04-24 21:34:11',	'authority',	'<unique_id>12</unique_id>',	'<unique_id>12</unique_id>',	2),
('2023-04-24 21:34:52',	'authority',	'<unique_id>14</unique_id>',	'<unique_id>14</unique_id>',	2),
('2023-04-23 19:05:59',	'authority',	'<unique_id>19</unique_id>',	'<unique_id>19</unique_id>',	1),
('2023-04-24 21:34:11',	'authority',	'<unique_id>2</unique_id>',	'<unique_id>2</unique_id>',	2),
('2023-04-22 21:04:01',	'brand',	'<id>82</id>',	'<id>82</id>',	1),
('2023-04-25 20:07:21',	'cart',	'<id>12</id>',	'<id>12</id>',	2),
('2023-04-25 21:21:20',	'cart',	'<id>14</id>',	'<id>14</id>',	2),
('2023-04-24 22:02:39',	'cart',	'<id>19</id>',	'<id>19</id>',	2),
('2023-04-24 22:07:27',	'cart',	'<id>1</id>',	'<id>1</id>',	2),
('2023-04-23 23:47:20',	'cart',	'<id>22</id>',	'<id>22</id>',	2),
('2023-04-24 18:46:19',	'cart',	'<id>23</id>',	'<id>23</id>',	1),
('2023-04-25 21:07:36',	'cart',	'<id>2</id>',	'<id>2</id>',	2),
('2023-04-24 14:40:51',	'cart_detail',	'<id>167</id>',	'<id>167</id>',	3),
('2023-04-24 14:40:46',	'cart_detail',	'<id>168</id>',	'<id>168</id>',	3),
('2023-04-22 22:14:10',	'cart_detail',	'<id>180</id>',	'<id>180</id>',	3),
('2023-04-22 14:21:18',	'cart_detail',	'<id>226</id>',	'<id>226</id>',	3),
('2023-04-24 21:35:28',	'cart_detail',	'<id>227</id>',	'<id>227</id>',	3),
('2023-04-24 21:35:28',	'cart_detail',	'<id>228</id>',	'<id>228</id>',	3),
('2023-04-22 14:21:14',	'cart_detail',	'<id>229</id>',	'<id>229</id>',	3),
('2023-04-22 14:21:16',	'cart_detail',	'<id>230</id>',	'<id>230</id>',	3),
('2023-04-22 20:35:52',	'cart_detail',	'<id>243</id>',	'<id>243</id>',	1),
('2023-04-24 14:18:25',	'cart_detail',	'<id>352</id>',	'<id>352</id>',	1),
('2023-04-24 18:46:19',	'cart_detail',	'<id>356</id>',	'<id>356</id>',	1),
('2023-04-24 21:24:50',	'cart_detail',	'<id>359</id>',	'<id>359</id>',	1),
('2023-04-24 21:24:52',	'cart_detail',	'<id>360</id>',	'<id>360</id>',	1),
('2023-04-24 22:03:14',	'cart_detail',	'<id>366</id>',	'<id>366</id>',	1),
('2023-04-24 22:03:30',	'cart_detail',	'<id>368</id>',	'<id>368</id>',	1),
('2023-04-24 22:03:38',	'cart_detail',	'<id>369</id>',	'<id>369</id>',	1),
('2023-04-24 22:03:52',	'cart_detail',	'<id>372</id>',	'<id>372</id>',	1),
('2023-04-24 22:07:22',	'cart_detail',	'<id>373</id>',	'<id>373</id>',	1),
('2023-04-24 22:26:20',	'cart_detail',	'<id>375</id>',	'<id>375</id>',	1),
('2023-04-25 19:12:34',	'cart_detail',	'<id>383</id>',	'<id>383</id>',	1),
('2023-04-24 22:40:31',	'category',	'<id>43</id>',	'<id>43</id>',	3),
('2023-04-24 21:33:24',	'category',	'<id>45</id>',	'<id>45</id>',	1),
('2023-04-25 21:21:27',	'hibernate_sequence',	'<next_val>1507</next_val>',	'<next_val>1429</next_val>',	2),
('2023-04-22 21:12:43',	'notification',	'<id>125</id>',	'<id>125</id>',	3),
('2023-04-22 18:39:42',	'order_detail',	'<id>125</id>',	'<id>125</id>',	1),
('2023-04-22 18:45:11',	'order_detail',	'<id>126</id>',	'<id>126</id>',	1),
('2023-04-22 22:14:10',	'order_detail',	'<id>127</id>',	'<id>127</id>',	1),
('2023-04-22 22:14:10',	'order_detail',	'<id>128</id>',	'<id>128</id>',	1),
('2023-04-22 22:14:10',	'order_detail',	'<id>129</id>',	'<id>129</id>',	1),
('2023-04-22 22:14:10',	'order_detail',	'<id>130</id>',	'<id>130</id>',	1),
('2023-04-22 22:34:12',	'order_detail',	'<id>131</id>',	'<id>131</id>',	1),
('2023-04-22 22:34:12',	'order_detail',	'<id>132</id>',	'<id>132</id>',	1),
('2023-04-22 23:56:48',	'order_detail',	'<id>133</id>',	'<id>133</id>',	1),
('2023-04-22 23:57:25',	'order_detail',	'<id>134</id>',	'<id>134</id>',	1),
('2023-04-23 00:06:46',	'order_detail',	'<id>135</id>',	'<id>135</id>',	1),
('2023-04-23 00:06:46',	'order_detail',	'<id>136</id>',	'<id>136</id>',	1),
('2023-04-23 00:07:17',	'order_detail',	'<id>137</id>',	'<id>137</id>',	1),
('2023-04-23 00:08:07',	'order_detail',	'<id>138</id>',	'<id>138</id>',	1),
('2023-04-23 00:23:38',	'order_detail',	'<id>139</id>',	'<id>139</id>',	1),
('2023-04-23 00:24:09',	'order_detail',	'<id>140</id>',	'<id>140</id>',	1),
('2023-04-23 00:24:35',	'order_detail',	'<id>141</id>',	'<id>141</id>',	1),
('2023-04-23 00:31:31',	'order_detail',	'<id>142</id>',	'<id>142</id>',	1),
('2023-04-23 00:31:56',	'order_detail',	'<id>143</id>',	'<id>143</id>',	1),
('2023-04-23 10:28:01',	'order_detail',	'<id>144</id>',	'<id>144</id>',	1),
('2023-04-23 10:29:08',	'order_detail',	'<id>145</id>',	'<id>145</id>',	1),
('2023-04-23 11:28:05',	'order_detail',	'<id>146</id>',	'<id>146</id>',	1),
('2023-04-23 12:28:43',	'order_detail',	'<id>147</id>',	'<id>147</id>',	1),
('2023-04-23 22:50:26',	'order_detail',	'<id>148</id>',	'<id>148</id>',	1),
('2023-04-23 22:50:26',	'order_detail',	'<id>149</id>',	'<id>149</id>',	1),
('2023-04-23 22:50:26',	'order_detail',	'<id>150</id>',	'<id>150</id>',	1),
('2023-04-23 22:51:58',	'order_detail',	'<id>151</id>',	'<id>151</id>',	1),
('2023-04-23 23:05:31',	'order_detail',	'<id>152</id>',	'<id>152</id>',	1),
('2023-04-23 23:05:31',	'order_detail',	'<id>153</id>',	'<id>153</id>',	1),
('2023-04-23 23:07:40',	'order_detail',	'<id>154</id>',	'<id>154</id>',	1),
('2023-04-23 23:07:41',	'order_detail',	'<id>155</id>',	'<id>155</id>',	1),
('2023-04-23 23:47:20',	'order_detail',	'<id>156</id>',	'<id>156</id>',	1),
('2023-04-24 21:21:01',	'order_detail',	'<id>157</id>',	'<id>157</id>',	1),
('2023-04-24 21:21:01',	'order_detail',	'<id>158</id>',	'<id>158</id>',	1),
('2023-04-24 21:35:28',	'order_detail',	'<id>159</id>',	'<id>159</id>',	1),
('2023-04-24 21:35:28',	'order_detail',	'<id>160</id>',	'<id>160</id>',	1),
('2023-04-24 21:35:28',	'order_detail',	'<id>161</id>',	'<id>161</id>',	1),
('2023-04-24 21:36:12',	'order_detail',	'<id>162</id>',	'<id>162</id>',	1),
('2023-04-24 21:36:12',	'order_detail',	'<id>163</id>',	'<id>163</id>',	1),
('2023-04-24 22:36:43',	'order_detail',	'<id>164</id>',	'<id>164</id>',	1),
('2023-04-24 22:36:43',	'order_detail',	'<id>165</id>',	'<id>165</id>',	1),
('2023-04-24 22:36:43',	'order_detail',	'<id>166</id>',	'<id>166</id>',	1),
('2023-04-24 22:41:53',	'order_detail',	'<id>167</id>',	'<id>167</id>',	1),
('2023-04-24 22:41:53',	'order_detail',	'<id>168</id>',	'<id>168</id>',	1),
('2023-04-24 22:41:53',	'order_detail',	'<id>169</id>',	'<id>169</id>',	1),
('2023-04-24 22:41:53',	'order_detail',	'<id>170</id>',	'<id>170</id>',	1),
('2023-04-25 13:29:02',	'order_detail',	'<id>171</id>',	'<id>171</id>',	1),
('2023-04-25 13:29:02',	'order_detail',	'<id>172</id>',	'<id>172</id>',	1),
('2023-04-25 13:30:01',	'order_detail',	'<id>173</id>',	'<id>173</id>',	1),
('2023-04-25 13:30:01',	'order_detail',	'<id>174</id>',	'<id>174</id>',	1),
('2023-04-25 13:30:57',	'order_detail',	'<id>175</id>',	'<id>175</id>',	1),
('2023-04-25 13:24:07',	'order_detail',	'<id>42</id>',	'<id>42</id>',	2),
('2023-04-25 13:24:07',	'order_detail',	'<id>43</id>',	'<id>43</id>',	2),
('2023-04-25 13:25:00',	'order_detail',	'<id>49</id>',	'<id>49</id>',	2),
('2023-04-23 22:58:16',	'orders',	'<id>100</id>',	'<id>100</id>',	1),
('2023-04-23 22:56:42',	'orders',	'<id>101</id>',	'<id>101</id>',	1),
('2023-04-23 22:56:42',	'orders',	'<id>102</id>',	'<id>102</id>',	1),
('2023-04-23 22:56:42',	'orders',	'<id>103</id>',	'<id>103</id>',	1),
('2023-04-23 22:56:42',	'orders',	'<id>104</id>',	'<id>104</id>',	1),
('2023-04-23 22:56:42',	'orders',	'<id>105</id>',	'<id>105</id>',	1),
('2023-04-23 22:57:08',	'orders',	'<id>106</id>',	'<id>106</id>',	1),
('2023-04-23 22:56:42',	'orders',	'<id>107</id>',	'<id>107</id>',	1),
('2023-04-23 23:07:04',	'orders',	'<id>108</id>',	'<id>108</id>',	1),
('2023-04-23 23:10:05',	'orders',	'<id>109</id>',	'<id>109</id>',	1),
('2023-04-23 23:14:16',	'orders',	'<id>110</id>',	'<id>110</id>',	1),
('2023-04-24 01:02:24',	'orders',	'<id>111</id>',	'<id>111</id>',	1),
('2023-04-24 21:21:02',	'orders',	'<id>112</id>',	'<id>112</id>',	1),
('2023-04-24 21:35:28',	'orders',	'<id>113</id>',	'<id>113</id>',	1),
('2023-04-24 21:36:36',	'orders',	'<id>114</id>',	'<id>114</id>',	1),
('2023-04-24 22:43:07',	'orders',	'<id>115</id>',	'<id>115</id>',	1),
('2023-04-25 15:30:16',	'orders',	'<id>116</id>',	'<id>116</id>',	1),
('2023-04-25 15:30:21',	'orders',	'<id>117</id>',	'<id>117</id>',	1),
('2023-04-25 13:51:54',	'orders',	'<id>118</id>',	'<id>118</id>',	1),
('2023-04-25 13:31:26',	'orders',	'<id>119</id>',	'<id>119</id>',	1),
('2023-04-25 13:21:57',	'orders',	'<id>23</id>',	'<id>23</id>',	2),
('2023-04-25 13:27:43',	'orders',	'<id>24</id>',	'<id>24</id>',	2),
('2023-04-25 13:28:20',	'orders',	'<id>25</id>',	'<id>25</id>',	2),
('2023-04-25 13:23:10',	'orders',	'<id>26</id>',	'<id>26</id>',	2),
('2023-04-25 13:32:56',	'orders',	'<id>27</id>',	'<id>27</id>',	2),
('2023-04-25 13:28:20',	'orders',	'<id>28</id>',	'<id>28</id>',	2),
('2023-04-25 13:32:06',	'orders',	'<id>29</id>',	'<id>29</id>',	2),
('2023-04-25 13:32:06',	'orders',	'<id>30</id>',	'<id>30</id>',	2),
('2023-04-25 13:20:23',	'orders',	'<id>33</id>',	'<id>33</id>',	2),
('2023-04-24 21:25:55',	'orders',	'<id>79</id>',	'<id>79</id>',	2),
('2023-04-23 23:10:24',	'orders',	'<id>82</id>',	'<id>82</id>',	2),
('2023-04-23 23:24:15',	'orders',	'<id>87</id>',	'<id>87</id>',	2),
('2023-04-22 22:36:32',	'orders',	'<id>88</id>',	'<id>88</id>',	1),
('2023-04-22 22:36:41',	'orders',	'<id>89</id>',	'<id>89</id>',	1),
('2023-04-24 00:58:09',	'orders',	'<id>90</id>',	'<id>90</id>',	1),
('2023-04-22 22:36:44',	'orders',	'<id>91</id>',	'<id>91</id>',	1),
('2023-04-23 23:10:29',	'orders',	'<id>92</id>',	'<id>92</id>',	1),
('2023-04-22 23:57:47',	'orders',	'<id>93</id>',	'<id>93</id>',	1),
('2023-04-23 00:07:00',	'orders',	'<id>94</id>',	'<id>94</id>',	1),
('2023-04-23 00:08:50',	'orders',	'<id>95</id>',	'<id>95</id>',	1),
('2023-04-23 00:08:53',	'orders',	'<id>96</id>',	'<id>96</id>',	1),
('2023-04-23 23:10:32',	'orders',	'<id>97</id>',	'<id>97</id>',	1),
('2023-04-23 22:58:16',	'orders',	'<id>98</id>',	'<id>98</id>',	1),
('2023-04-23 22:58:16',	'orders',	'<id>99</id>',	'<id>99</id>',	1),
('2023-04-25 21:13:17',	'product',	'<id>100</id>',	'<id>100</id>',	2),
('2023-04-25 21:13:19',	'product',	'<id>104</id>',	'<id>104</id>',	2),
('2023-04-25 21:13:22',	'product',	'<id>105</id>',	'<id>105</id>',	2),
('2023-04-25 21:13:57',	'product',	'<id>109</id>',	'<id>109</id>',	2),
('2023-04-25 21:17:47',	'product',	'<id>110</id>',	'<id>110</id>',	2),
('2023-04-25 21:13:58',	'product',	'<id>111</id>',	'<id>111</id>',	2),
('2023-04-25 21:13:59',	'product',	'<id>117</id>',	'<id>117</id>',	1),
('2023-04-25 21:14:00',	'product',	'<id>118</id>',	'<id>118</id>',	1),
('2023-04-25 21:14:00',	'product',	'<id>119</id>',	'<id>119</id>',	1),
('2023-04-25 21:14:01',	'product',	'<id>120</id>',	'<id>120</id>',	1),
('2023-04-25 21:22:40',	'product',	'<id>121</id>',	'<id>121</id>',	1),
('2023-04-25 21:14:03',	'product',	'<id>122</id>',	'<id>122</id>',	1),
('2023-04-25 21:14:03',	'product',	'<id>123</id>',	'<id>123</id>',	1),
('2023-04-25 21:14:06',	'product',	'<id>124</id>',	'<id>124</id>',	1),
('2023-04-25 21:13:00',	'product',	'<id>93</id>',	'<id>93</id>',	2),
('2023-04-25 21:13:03',	'product',	'<id>94</id>',	'<id>94</id>',	2),
('2023-04-25 21:13:04',	'product',	'<id>95</id>',	'<id>95</id>',	2),
('2023-04-25 21:13:07',	'product',	'<id>96</id>',	'<id>96</id>',	2),
('2023-04-25 21:13:10',	'product',	'<id>97</id>',	'<id>97</id>',	2),
('2023-04-25 21:13:12',	'product',	'<id>98</id>',	'<id>98</id>',	2),
('2023-04-25 21:13:15',	'product',	'<id>99</id>',	'<id>99</id>',	2),
('2023-04-23 09:46:32',	'product_attribute',	'<id>125</id>',	'<id>125</id>',	2),
('2023-04-22 21:08:03',	'product_attribute',	'<id>126</id>',	'<id>126</id>',	1),
('2023-04-23 09:46:32',	'product_attribute',	'<id>130</id>',	'<id>130</id>',	1),
('2023-04-23 09:46:32',	'product_attribute',	'<id>131</id>',	'<id>131</id>',	1),
('2023-04-23 09:46:32',	'product_attribute',	'<id>132</id>',	'<id>132</id>',	1),
('2023-04-23 09:46:32',	'product_attribute',	'<id>133</id>',	'<id>133</id>',	1),
('2023-04-23 09:46:32',	'product_attribute',	'<id>134</id>',	'<id>134</id>',	1),
('2023-04-23 09:46:32',	'product_attribute',	'<id>135</id>',	'<id>135</id>',	1),
('2023-04-23 09:46:32',	'product_attribute',	'<id>136</id>',	'<id>136</id>',	1),
('2023-04-23 09:46:32',	'product_attribute',	'<id>137</id>',	'<id>137</id>',	1),
('2023-04-23 09:46:32',	'product_attribute',	'<id>138</id>',	'<id>138</id>',	1),
('2023-04-23 09:59:23',	'product_attribute',	'<id>139</id>',	'<id>139</id>',	1),
('2023-04-23 09:59:23',	'product_attribute',	'<id>140</id>',	'<id>140</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>141</id>',	'<id>141</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>142</id>',	'<id>142</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>143</id>',	'<id>143</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>144</id>',	'<id>144</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>145</id>',	'<id>145</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>146</id>',	'<id>146</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>147</id>',	'<id>147</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>148</id>',	'<id>148</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>149</id>',	'<id>149</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>150</id>',	'<id>150</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>151</id>',	'<id>151</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>152</id>',	'<id>152</id>',	1),
('2023-04-23 09:59:24',	'product_attribute',	'<id>153</id>',	'<id>153</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>154</id>',	'<id>154</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>155</id>',	'<id>155</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>156</id>',	'<id>156</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>157</id>',	'<id>157</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>158</id>',	'<id>158</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>159</id>',	'<id>159</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>160</id>',	'<id>160</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>161</id>',	'<id>161</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>162</id>',	'<id>162</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>163</id>',	'<id>163</id>',	1),
('2023-04-23 10:17:05',	'product_attribute',	'<id>164</id>',	'<id>164</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>165</id>',	'<id>165</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>166</id>',	'<id>166</id>',	1),
('2023-04-23 09:59:25',	'product_attribute',	'<id>167</id>',	'<id>167</id>',	1),
('2023-04-23 09:59:26',	'product_attribute',	'<id>168</id>',	'<id>168</id>',	1),
('2023-04-23 09:59:26',	'product_attribute',	'<id>169</id>',	'<id>169</id>',	1),
('2023-04-23 09:59:27',	'product_attribute',	'<id>170</id>',	'<id>170</id>',	1),
('2023-04-23 09:59:27',	'product_attribute',	'<id>171</id>',	'<id>171</id>',	1),
('2023-04-23 09:59:27',	'product_attribute',	'<id>172</id>',	'<id>172</id>',	1),
('2023-04-23 09:59:27',	'product_attribute',	'<id>173</id>',	'<id>173</id>',	1),
('2023-04-23 09:59:27',	'product_attribute',	'<id>174</id>',	'<id>174</id>',	1),
('2023-04-23 09:59:27',	'product_attribute',	'<id>175</id>',	'<id>175</id>',	1),
('2023-04-23 09:59:27',	'product_attribute',	'<id>176</id>',	'<id>176</id>',	1),
('2023-04-23 09:59:27',	'product_attribute',	'<id>177</id>',	'<id>177</id>',	1),
('2023-04-23 09:59:27',	'product_attribute',	'<id>178</id>',	'<id>178</id>',	1),
('2023-04-23 09:59:27',	'product_attribute',	'<id>179</id>',	'<id>179</id>',	1),
('2023-04-23 09:59:27',	'product_attribute',	'<id>180</id>',	'<id>180</id>',	1),
('2023-04-23 10:17:06',	'product_attribute',	'<id>181</id>',	'<id>181</id>',	1),
('2023-04-23 10:17:06',	'product_attribute',	'<id>182</id>',	'<id>182</id>',	1),
('2023-04-23 10:17:06',	'product_attribute',	'<id>183</id>',	'<id>183</id>',	1),
('2023-04-23 10:17:07',	'product_attribute',	'<id>184</id>',	'<id>184</id>',	1),
('2023-04-23 10:17:07',	'product_attribute',	'<id>185</id>',	'<id>185</id>',	1),
('2023-04-23 10:17:07',	'product_attribute',	'<id>186</id>',	'<id>186</id>',	1),
('2023-04-23 10:17:07',	'product_attribute',	'<id>187</id>',	'<id>187</id>',	1),
('2023-04-23 10:17:07',	'product_attribute',	'<id>188</id>',	'<id>188</id>',	1),
('2023-04-23 10:17:07',	'product_attribute',	'<id>189</id>',	'<id>189</id>',	1),
('2023-04-23 10:17:07',	'product_attribute',	'<id>190</id>',	'<id>190</id>',	1),
('2023-04-23 10:17:07',	'product_attribute',	'<id>191</id>',	'<id>191</id>',	1),
('2023-04-23 10:17:07',	'product_attribute',	'<id>192</id>',	'<id>192</id>',	1),
('2023-04-23 10:17:07',	'product_attribute',	'<id>193</id>',	'<id>193</id>',	1),
('2023-04-23 10:17:08',	'product_attribute',	'<id>194</id>',	'<id>194</id>',	1),
('2023-04-23 10:17:08',	'product_attribute',	'<id>195</id>',	'<id>195</id>',	1),
('2023-04-23 10:17:08',	'product_attribute',	'<id>196</id>',	'<id>196</id>',	1),
('2023-04-23 10:17:08',	'product_attribute',	'<id>197</id>',	'<id>197</id>',	1),
('2023-04-23 10:17:08',	'product_attribute',	'<id>198</id>',	'<id>198</id>',	1),
('2023-04-23 10:17:08',	'product_attribute',	'<id>199</id>',	'<id>199</id>',	1),
('2023-04-23 10:17:08',	'product_attribute',	'<id>200</id>',	'<id>200</id>',	1),
('2023-04-23 10:17:08',	'product_attribute',	'<id>201</id>',	'<id>201</id>',	1),
('2023-04-23 10:17:08',	'product_attribute',	'<id>202</id>',	'<id>202</id>',	1),
('2023-04-23 10:17:08',	'product_attribute',	'<id>203</id>',	'<id>203</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>204</id>',	'<id>204</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>205</id>',	'<id>205</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>206</id>',	'<id>206</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>207</id>',	'<id>207</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>208</id>',	'<id>208</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>209</id>',	'<id>209</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>210</id>',	'<id>210</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>211</id>',	'<id>211</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>212</id>',	'<id>212</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>213</id>',	'<id>213</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>214</id>',	'<id>214</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>215</id>',	'<id>215</id>',	1),
('2023-04-23 10:17:09',	'product_attribute',	'<id>216</id>',	'<id>216</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>217</id>',	'<id>217</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>218</id>',	'<id>218</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>219</id>',	'<id>219</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>220</id>',	'<id>220</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>221</id>',	'<id>221</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>222</id>',	'<id>222</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>223</id>',	'<id>223</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>224</id>',	'<id>224</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>225</id>',	'<id>225</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>226</id>',	'<id>226</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>227</id>',	'<id>227</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>228</id>',	'<id>228</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>229</id>',	'<id>229</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>230</id>',	'<id>230</id>',	1),
('2023-04-23 10:17:10',	'product_attribute',	'<id>231</id>',	'<id>231</id>',	1),
('2023-04-23 10:17:11',	'product_attribute',	'<id>232</id>',	'<id>232</id>',	1),
('2023-04-23 10:17:11',	'product_attribute',	'<id>233</id>',	'<id>233</id>',	1),
('2023-04-23 10:17:11',	'product_attribute',	'<id>234</id>',	'<id>234</id>',	1),
('2023-04-23 10:17:11',	'product_attribute',	'<id>235</id>',	'<id>235</id>',	1),
('2023-04-23 10:17:11',	'product_attribute',	'<id>236</id>',	'<id>236</id>',	1),
('2023-04-23 10:17:11',	'product_attribute',	'<id>237</id>',	'<id>237</id>',	1),
('2023-04-23 10:17:11',	'product_attribute',	'<id>238</id>',	'<id>238</id>',	1),
('2023-04-23 10:21:00',	'product_attribute',	'<id>240</id>',	'<id>240</id>',	1),
('2023-04-23 10:21:00',	'product_attribute',	'<id>241</id>',	'<id>241</id>',	1),
('2023-04-23 10:21:00',	'product_attribute',	'<id>242</id>',	'<id>242</id>',	1),
('2023-04-23 10:21:00',	'product_attribute',	'<id>243</id>',	'<id>243</id>',	1),
('2023-04-23 10:21:00',	'product_attribute',	'<id>244</id>',	'<id>244</id>',	1),
('2023-04-23 10:21:01',	'product_attribute',	'<id>245</id>',	'<id>245</id>',	1),
('2023-04-23 10:21:01',	'product_attribute',	'<id>246</id>',	'<id>246</id>',	1),
('2023-04-23 10:21:01',	'product_attribute',	'<id>247</id>',	'<id>247</id>',	1),
('2023-04-23 10:21:01',	'product_attribute',	'<id>248</id>',	'<id>248</id>',	1),
('2023-04-23 10:21:01',	'product_attribute',	'<id>249</id>',	'<id>249</id>',	1),
('2023-04-23 10:21:01',	'product_attribute',	'<id>300</id>',	'<id>300</id>',	1),
('2023-04-23 10:48:07',	'product_attribute',	'<id>302</id>',	'<id>302</id>',	1),
('2023-04-23 10:48:07',	'product_attribute',	'<id>303</id>',	'<id>303</id>',	1),
('2023-04-23 10:48:07',	'product_attribute',	'<id>304</id>',	'<id>304</id>',	1),
('2023-04-23 10:48:07',	'product_attribute',	'<id>305</id>',	'<id>305</id>',	1),
('2023-04-23 10:48:07',	'product_attribute',	'<id>306</id>',	'<id>306</id>',	1),
('2023-04-23 10:48:07',	'product_attribute',	'<id>307</id>',	'<id>307</id>',	1),
('2023-04-23 10:48:07',	'product_attribute',	'<id>308</id>',	'<id>308</id>',	1),
('2023-04-23 10:48:07',	'product_attribute',	'<id>309</id>',	'<id>309</id>',	1),
('2023-04-23 10:48:07',	'product_attribute',	'<id>310</id>',	'<id>310</id>',	1),
('2023-04-23 15:47:05',	'product_attribute',	'<id>311</id>',	'<id>311</id>',	1),
('2023-04-23 15:47:21',	'product_attribute',	'<id>312</id>',	'<id>312</id>',	1),
('2023-04-23 15:47:40',	'product_attribute',	'<id>313</id>',	'<id>313</id>',	1),
('2023-04-24 17:08:18',	'product_attribute',	'<id>320</id>',	'<id>320</id>',	1),
('2023-04-24 17:08:18',	'product_attribute',	'<id>323</id>',	'<id>323</id>',	1),
('2023-04-24 17:08:18',	'product_attribute',	'<id>324</id>',	'<id>324</id>',	1),
('2023-04-24 17:08:18',	'product_attribute',	'<id>325</id>',	'<id>325</id>',	1),
('2023-04-24 17:08:18',	'product_attribute',	'<id>326</id>',	'<id>326</id>',	1),
('2023-04-24 17:08:18',	'product_attribute',	'<id>327</id>',	'<id>327</id>',	1),
('2023-04-24 17:08:19',	'product_attribute',	'<id>328</id>',	'<id>328</id>',	1),
('2023-04-24 17:08:19',	'product_attribute',	'<id>329</id>',	'<id>329</id>',	1),
('2023-04-24 17:08:18',	'product_attribute',	'<id>330</id>',	'<id>330</id>',	1),
('2023-04-24 21:29:06',	'product_attribute',	'<id>331</id>',	'<id>331</id>',	1),
('2023-04-24 22:27:27',	'product_attribute',	'<id>335</id>',	'<id>335</id>',	1),
('2023-04-24 22:28:26',	'product_attribute',	'<id>337</id>',	'<id>337</id>',	1),
('2023-04-24 22:26:02',	'product_variant',	'<id>55</id>',	'<id>55</id>',	2),
('2023-04-24 22:41:54',	'product_variant',	'<id>56</id>',	'<id>56</id>',	2),
('2023-04-24 22:41:54',	'product_variant',	'<id>57</id>',	'<id>57</id>',	2),
('2023-04-25 13:30:02',	'product_variant',	'<id>58</id>',	'<id>58</id>',	2),
('2023-04-23 12:23:22',	'product_variant',	'<id>59</id>',	'<id>59</id>',	2),
('2023-04-23 22:50:27',	'product_variant',	'<id>60</id>',	'<id>60</id>',	2),
('2023-04-23 22:50:27',	'product_variant',	'<id>61</id>',	'<id>61</id>',	2),
('2023-04-23 22:51:59',	'product_variant',	'<id>62</id>',	'<id>62</id>',	2),
('2023-04-24 22:36:44',	'product_variant',	'<id>63</id>',	'<id>63</id>',	2),
('2023-04-24 22:36:44',	'product_variant',	'<id>64</id>',	'<id>64</id>',	2),
('2023-04-22 22:36:45',	'product_variant',	'<id>65</id>',	'<id>65</id>',	2),
('2023-04-25 13:29:03',	'product_variant',	'<id>66</id>',	'<id>66</id>',	2),
('2023-04-25 13:30:02',	'product_variant',	'<id>67</id>',	'<id>67</id>',	2),
('2023-04-25 13:30:58',	'product_variant',	'<id>68</id>',	'<id>68</id>',	2),
('2023-04-24 22:39:46',	'product_variant',	'<id>70</id>',	'<id>70</id>',	2),
('2023-04-24 21:35:29',	'product_variant',	'<id>71</id>',	'<id>71</id>',	2),
('2023-04-23 23:05:32',	'product_variant',	'<id>72</id>',	'<id>72</id>',	2),
('2023-04-23 23:10:33',	'product_variant',	'<id>76</id>',	'<id>76</id>',	1),
('2023-04-22 21:19:19',	'product_variant',	'<id>77</id>',	'<id>77</id>',	1),
('2023-04-24 22:07:19',	'product_variant',	'<id>78</id>',	'<id>78</id>',	1),
('2023-04-24 16:53:59',	'product_variant',	'<id>81</id>',	'<id>81</id>',	1),
('2023-04-24 22:41:54',	'product_variant',	'<id>82</id>',	'<id>82</id>',	1),
('2023-04-24 22:41:54',	'product_variant',	'<id>83</id>',	'<id>83</id>',	1),
('2023-04-24 17:01:38',	'product_variant',	'<id>85</id>',	'<id>85</id>',	1),
('2023-04-24 21:30:29',	'product_variant',	'<id>86</id>',	'<id>86</id>',	1),
('2023-04-25 21:19:01',	'promotion_product',	'<id>18</id>',	'<id>18</id>',	1),
('2023-04-25 21:18:41',	'promotion_product',	'<id>19</id>',	'<id>19</id>',	1),
('2023-04-25 21:18:31',	'promotion_product',	'<id>1</id>',	'<id>1</id>',	2),
('2023-04-25 21:18:34',	'promotion_product',	'<id>2</id>',	'<id>2</id>',	2),
('2023-04-23 17:35:06',	'promotion_type',	'<id>12</id>',	'<id>12</id>',	1),
('2023-04-23 17:35:07',	'promotion_type',	'<id>13</id>',	'<id>13</id>',	1),
('2023-04-23 17:36:07',	'promotion_type',	'<id>14</id>',	'<id>14</id>',	1),
('2023-04-23 17:37:24',	'promotion_type',	'<id>15</id>',	'<id>15</id>',	1),
('2023-04-23 17:41:17',	'promotion_user',	'<id>10</id>',	'<id>10</id>',	1),
('2023-04-23 17:41:17',	'promotion_user',	'<id>11</id>',	'<id>11</id>',	1),
('2023-04-23 17:41:17',	'promotion_user',	'<id>12</id>',	'<id>12</id>',	1),
('2023-04-23 17:41:17',	'promotion_user',	'<id>13</id>',	'<id>13</id>',	1),
('2023-04-23 17:41:17',	'promotion_user',	'<id>14</id>',	'<id>14</id>',	1),
('2023-04-23 17:43:27',	'promotion_user',	'<id>15</id>',	'<id>15</id>',	1),
('2023-04-23 17:43:27',	'promotion_user',	'<id>16</id>',	'<id>16</id>',	1),
('2023-04-23 17:43:27',	'promotion_user',	'<id>17</id>',	'<id>17</id>',	1),
('2023-04-23 17:43:27',	'promotion_user',	'<id>18</id>',	'<id>18</id>',	1),
('2023-04-23 17:43:27',	'promotion_user',	'<id>19</id>',	'<id>19</id>',	1),
('2023-04-23 17:43:27',	'promotion_user',	'<id>20</id>',	'<id>20</id>',	1),
('2023-04-23 17:46:46',	'promotion_user',	'<id>21</id>',	'<id>21</id>',	1),
('2023-04-23 17:46:46',	'promotion_user',	'<id>22</id>',	'<id>22</id>',	1),
('2023-04-23 17:46:46',	'promotion_user',	'<id>23</id>',	'<id>23</id>',	1),
('2023-04-23 17:46:46',	'promotion_user',	'<id>24</id>',	'<id>24</id>',	1),
('2023-04-23 17:46:46',	'promotion_user',	'<id>25</id>',	'<id>25</id>',	1),
('2023-04-23 17:46:46',	'promotion_user',	'<id>26</id>',	'<id>26</id>',	1),
('2023-04-23 17:46:46',	'promotion_user',	'<id>27</id>',	'<id>27</id>',	1),
('2023-04-23 17:47:31',	'promotion_user',	'<id>28</id>',	'<id>28</id>',	1),
('2023-04-23 17:48:27',	'promotion_user',	'<id>29</id>',	'<id>29</id>',	1),
('2023-04-23 17:48:45',	'promotion_user',	'<id>30</id>',	'<id>30</id>',	1),
('2023-04-23 17:51:27',	'promotion_user',	'<id>31</id>',	'<id>31</id>',	1),
('2023-04-23 17:51:27',	'promotion_user',	'<id>32</id>',	'<id>32</id>',	1),
('2023-04-23 17:51:27',	'promotion_user',	'<id>33</id>',	'<id>33</id>',	1),
('2023-04-23 17:51:27',	'promotion_user',	'<id>34</id>',	'<id>34</id>',	1),
('2023-04-23 17:51:27',	'promotion_user',	'<id>35</id>',	'<id>35</id>',	1),
('2023-04-23 17:51:27',	'promotion_user',	'<id>36</id>',	'<id>36</id>',	1),
('2023-04-23 17:51:27',	'promotion_user',	'<id>37</id>',	'<id>37</id>',	1),
('2023-04-23 17:51:27',	'promotion_user',	'<id>38</id>',	'<id>38</id>',	1),
('2023-04-23 17:54:20',	'promotion_user',	'<id>39</id>',	'<id>39</id>',	1),
('2023-04-23 17:54:20',	'promotion_user',	'<id>40</id>',	'<id>40</id>',	1),
('2023-04-23 17:54:20',	'promotion_user',	'<id>41</id>',	'<id>41</id>',	1),
('2023-04-23 17:54:20',	'promotion_user',	'<id>42</id>',	'<id>42</id>',	1),
('2023-04-23 17:40:08',	'promotion_user',	'<id>8</id>',	'<id>8</id>',	1),
('2023-04-23 17:41:17',	'promotion_user',	'<id>9</id>',	'<id>9</id>',	1),
('2023-04-23 23:01:30',	'rating',	'<id>49</id>',	'<id>49</id>',	1),
('2023-04-23 23:01:30',	'rating',	'<id>50</id>',	'<id>50</id>',	1),
('2023-04-23 23:01:30',	'rating',	'<id>51</id>',	'<id>51</id>',	1),
('2023-04-23 23:11:00',	'rating',	'<id>52</id>',	'<id>52</id>',	1),
('2023-04-23 23:16:54',	'rating',	'<id>53</id>',	'<id>53</id>',	1),
('2023-04-23 23:42:21',	'rating',	'<id>54</id>',	'<id>54</id>',	1),
('2023-04-23 23:42:21',	'rating',	'<id>55</id>',	'<id>55</id>',	1),
('2023-04-24 21:25:48',	'rating',	'<id>56</id>',	'<id>56</id>',	1),
('2023-04-24 22:02:06',	'rating',	'<id>57</id>',	'<id>57</id>',	1),
('2023-04-24 22:02:12',	'rating',	'<id>58</id>',	'<id>58</id>',	1),
('2023-04-24 22:02:12',	'rating',	'<id>59</id>',	'<id>59</id>',	1),
('2023-04-24 22:02:18',	'rating',	'<id>60</id>',	'<id>60</id>',	1),
('2023-04-24 22:02:22',	'rating',	'<id>61</id>',	'<id>61</id>',	1),
('2023-04-24 22:02:30',	'rating',	'<id>62</id>',	'<id>62</id>',	1),
('2023-04-24 22:02:35',	'rating',	'<id>63</id>',	'<id>63</id>',	1),
('2023-04-24 22:02:40',	'rating',	'<id>64</id>',	'<id>64</id>',	1),
('2023-04-24 22:02:46',	'rating',	'<id>65</id>',	'<id>65</id>',	1),
('2023-04-24 22:02:53',	'rating',	'<id>66</id>',	'<id>66</id>',	1),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1277</id>',	'<id>1277</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1281</id>',	'<id>1281</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1282</id>',	'<id>1282</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1284</id>',	'<id>1284</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1286</id>',	'<id>1286</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1288</id>',	'<id>1288</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1291</id>',	'<id>1291</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1293</id>',	'<id>1293</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1294</id>',	'<id>1294</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1295</id>',	'<id>1295</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1296</id>',	'<id>1296</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1298</id>',	'<id>1298</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1299</id>',	'<id>1299</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1301</id>',	'<id>1301</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1310</id>',	'<id>1310</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1313</id>',	'<id>1313</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1319</id>',	'<id>1319</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1320</id>',	'<id>1320</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1321</id>',	'<id>1321</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1323</id>',	'<id>1323</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1324</id>',	'<id>1324</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1326</id>',	'<id>1326</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1328</id>',	'<id>1328</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1331</id>',	'<id>1331</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1333</id>',	'<id>1333</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1337</id>',	'<id>1337</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1342</id>',	'<id>1342</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1344</id>',	'<id>1344</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1346</id>',	'<id>1346</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1348</id>',	'<id>1348</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1352</id>',	'<id>1352</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1354</id>',	'<id>1354</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1365</id>',	'<id>1365</id>',	3),
('2023-04-22 17:49:05',	'refreshtoken',	'<id>1367</id>',	'<id>1367</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1375</id>',	'<id>1375</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1392</id>',	'<id>1392</id>',	3),
('2023-04-22 18:16:30',	'refreshtoken',	'<id>1399</id>',	'<id>1399</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1417</id>',	'<id>1417</id>',	3),
('2023-04-22 14:32:38',	'refreshtoken',	'<id>1418</id>',	'<id>1418</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1420</id>',	'<id>1420</id>',	3),
('2023-04-22 14:31:13',	'refreshtoken',	'<id>1423</id>',	'<id>1423</id>',	3),
('2023-04-22 14:41:24',	'refreshtoken',	'<id>1425</id>',	'<id>1425</id>',	3),
('2023-04-22 20:10:02',	'refreshtoken',	'<id>1426</id>',	'<id>1426</id>',	3),
('2023-04-22 20:56:21',	'refreshtoken',	'<id>1427</id>',	'<id>1427</id>',	3),
('2023-04-22 16:22:47',	'refreshtoken',	'<id>1428</id>',	'<id>1428</id>',	3),
('2023-04-22 22:15:29',	'refreshtoken',	'<id>1453</id>',	'<id>1453</id>',	1),
('2023-04-23 12:23:26',	'refreshtoken',	'<id>1457</id>',	'<id>1457</id>',	1),
('2023-04-23 18:59:21',	'refreshtoken',	'<id>1468</id>',	'<id>1468</id>',	1),
('2023-04-23 19:06:29',	'refreshtoken',	'<id>1469</id>',	'<id>1469</id>',	1),
('2023-04-24 14:32:48',	'refreshtoken',	'<id>1474</id>',	'<id>1474</id>',	1),
('2023-04-24 21:19:56',	'refreshtoken',	'<id>1478</id>',	'<id>1478</id>',	1),
('2023-04-24 21:24:50',	'refreshtoken',	'<id>1479</id>',	'<id>1479</id>',	1),
('2023-04-24 22:01:25',	'refreshtoken',	'<id>1488</id>',	'<id>1488</id>',	1),
('2023-04-24 22:41:45',	'refreshtoken',	'<id>1495</id>',	'<id>1495</id>',	1),
('2023-04-25 19:05:25',	'refreshtoken',	'<id>1497</id>',	'<id>1497</id>',	1),
('2023-04-25 21:07:44',	'refreshtoken',	'<id>1504</id>',	'<id>1504</id>',	1),
('2023-04-25 21:19:22',	'refreshtoken',	'<id>1505</id>',	'<id>1505</id>',	1),
('2023-04-25 21:21:27',	'refreshtoken',	'<id>1506</id>',	'<id>1506</id>',	1),
('2023-04-24 21:25:13',	'user',	'<id>1</id>',	'<id>1</id>',	2),
('2023-04-23 18:59:15',	'user',	'<id>45</id>',	'<id>45</id>',	1),
('2023-04-22 14:35:33',	'wishlist',	'<id>59</id>',	'<id>59</id>',	1),
('2023-04-22 14:35:37',	'wishlist',	'<id>60</id>',	'<id>60</id>',	1),
('2023-04-23 22:48:34',	'wishlist',	'<id>61</id>',	'<id>61</id>',	1),
('2023-04-23 22:49:20',	'wishlist',	'<id>62</id>',	'<id>62</id>',	1),
('2023-04-23 23:05:17',	'wishlist',	'<id>63</id>',	'<id>63</id>',	1),
('2023-04-23 23:05:18',	'wishlist',	'<id>64</id>',	'<id>64</id>',	1),
('2023-04-24 22:02:45',	'wishlist',	'<id>68</id>',	'<id>68</id>',	1),
('2023-04-24 22:24:28',	'wishlist',	'<id>69</id>',	'<id>69</id>',	1);

DROP TABLE IF EXISTS `notification`;
CREATE TABLE `notification` (
  `id` int NOT NULL AUTO_INCREMENT,
  `heading` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `path` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `subtitle` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `timestamp` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


DELIMITER ;;

CREATE TRIGGER `a_i_notification` AFTER INSERT ON `notification` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'notification'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_notification` AFTER UPDATE ON `notification` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'notification';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_notification` AFTER DELETE ON `notification` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'notification';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `opt_register`;
CREATE TABLE `opt_register` (
  `username` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `password` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `full_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `phone` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `otp_code` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
  `time_expire` datetime DEFAULT NULL,
  `is_verified` bit(1) DEFAULT NULL,
  PRIMARY KEY (`username`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `opt_register` (`username`, `password`, `email`, `full_name`, `phone`, `otp_code`, `time_expire`, `is_verified`) VALUES
('123',	'$2a$10$wxS4H.pGQ1jwwDKlEHZFFez.7OaqY.QurXBQhrd02ZBxGklHPPaTe',	'nguyenquoctai872@gmail.com',	'Nguyễn Quốc Tài ',	'123',	'3213',	'2023-04-13 10:58:58',	CONV('0', 2, 10) + 0),
('admin',	'$2a$10$bXWG6Pk1fEyAfie82CM3T.8aQipzNSCgn4nXAzfHQ20qu9FOhMnue',	'admin@gmail.com',	'Truong Hoang Long',	'0969777741',	'7652',	'2023-04-22 13:53:48',	CONV('0', 2, 10) + 0),
('anh123',	'$2a$10$ODOak.4ryNWQqhu42CkSK.46Wpr.SRDodhBEULsO7Al8k.AXlcg6a',	'lefoca5370@snowlash.com',	'Nguyễn Văn A',	'0981623789',	'6360',	'2023-04-15 03:58:03',	CONV('0', 2, 10) + 0),
('ebonik',	'$2a$10$OdqZR5DVpNtaYxQ5kqoozebJ37SchZlpCe7VPvlmvBnXiInteA9vW',	'ebonikshope@gmail.com',	'ebonik',	'0394675679',	'1931',	'2023-04-15 07:13:10',	CONV('0', 2, 10) + 0),
('hieu2510',	'$2a$10$hz/md.d9B8kcxCvc0uWFEu9KKX2/i59JQc6xnWNuxUgp5iKSciPgu',	'hieuhvps19146@fpt.edu.vn',	'Hiếu',	'776274144',	'4863',	'2023-04-09 13:07:19',	CONV('0', 2, 10) + 0),
('hieuadmin',	'$2a$10$3O8XABuCK17cTTca7.3GCu/1t8ZFDBDIPt.owz/eNmTtRLe43dKC6',	'hieuhvps19146@fpt.edu.vn',	'Hoàng Văn Hiếu',	'0776274144',	'9924',	'2023-04-08 14:44:19',	CONV('0', 2, 10) + 0),
('string',	'$2a$10$VJlMmh/nROvhKX.pytRf8evggBdHNK3XV5vHvjDFfWkzLGTiK7NAq',	'synhatphu2@gmail.com',	'string',	'0344963174',	'2000',	'2023-04-14 22:47:05',	CONV('0', 2, 10) + 0),
('Test',	'$2a$10$kB5IHCCbFASSlvgmh1Q4ZeH52HF2b98YO7hAtnF3uafX4F6J0/20.',	'testguestagain@gmail.com',	'Test',	'',	'7319',	'2023-04-10 14:46:18',	CONV('0', 2, 10) + 0),
('user1',	'$2a$10$.nONdRp5kmD8wc/YgF6aQeL3EkIF2ahL7te4/ANO8rb2vwvJH1eAO',	'hieuhoang25102001td@gmail.com',	'Hiếu',	'776274144',	'1265',	'2023-04-11 01:10:42',	CONV('0', 2, 10) + 0),
('vongadmin',	'$2a$10$oR47K4q.wUNug1s6aP98QOGjfFznLZeMJn9cvdED10naSlx4AfOw.',	'vong.huynh@aegona.com',	'vanvong',	'0987132367',	'5047',	'2023-04-08 11:55:37',	CONV('0', 2, 10) + 0),
('vonghuynh',	'$2a$10$bnLAzOY9KEd3eM7x9OjS.exfBQBIu7ZvtALpuoVWwohGNGWDoC1aa',	'huynhvanvong2002@gmail.com',	'huynh van vong',	'0987132367',	'9637',	'2023-04-15 03:56:10',	CONV('0', 2, 10) + 0);

DELIMITER ;;

CREATE TRIGGER `a_i_opt_register` AFTER INSERT ON `opt_register` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'opt_register'; 						SET @pk_d = CONCAT('<username>',NEW.`username`,'</username>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_opt_register` AFTER UPDATE ON `opt_register` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'opt_register';						SET @pk_d_old = CONCAT('<username>',OLD.`username`,'</username>');						SET @pk_d = CONCAT('<username>',NEW.`username`,'</username>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_opt_register` AFTER DELETE ON `opt_register` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'opt_register';						SET @pk_d = CONCAT('<username>',OLD.`username`,'</username>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `order_detail`;
CREATE TABLE `order_detail` (
  `id` int NOT NULL AUTO_INCREMENT,
  `order_id` int DEFAULT NULL,
  `product_variant_id` int DEFAULT NULL,
  `create_date` datetime DEFAULT NULL,
  `price_sum` double DEFAULT NULL,
  `promotion_value` double DEFAULT NULL,
  `quantity` int DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  KEY `fk_order_detail_orders_1` (`order_id`) USING BTREE,
  KEY `fk_order_detail_product_variant_1` (`product_variant_id`) USING BTREE,
  CONSTRAINT `fk_order_detail_orders_1` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_order_detail_product_variant_1` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variant` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `order_detail` (`id`, `order_id`, `product_variant_id`, `create_date`, `price_sum`, `promotion_value`, `quantity`) VALUES
(42,	23,	66,	'2023-03-13 00:17:29',	129900000,	6495000,	1),
(43,	24,	67,	'2023-03-12 17:18:36',	8790000,	1758000,	1),
(44,	25,	68,	'2023-04-13 13:54:38',	34000000,	3400000,	1),
(45,	26,	66,	'2023-04-13 13:56:50',	12990000,	6495000,	1),
(46,	27,	66,	'2023-04-13 23:23:22',	12990000,	6495000,	1),
(47,	27,	56,	'2023-04-13 23:23:22',	23890000,	11945000,	1),
(48,	27,	57,	'2023-04-13 23:23:22',	23890000,	11945000,	1),
(49,	28,	65,	'2023-04-14 14:38:22',	229900000,	0,	1),
(50,	29,	65,	'2023-04-14 14:39:42',	22990000,	0,	1),
(51,	30,	57,	'2023-04-14 14:43:06',	23890000,	0,	1),
(52,	31,	67,	'2023-04-14 14:47:52',	8790000,	0,	1),
(53,	32,	59,	'2023-04-14 14:49:13',	20390000,	0,	1),
(55,	34,	67,	'2023-04-14 14:52:05',	8790000,	0,	1),
(56,	35,	59,	'2023-04-14 14:53:18',	20390000,	0,	1),
(57,	36,	66,	'2023-04-14 14:54:52',	12990000,	0,	1),
(58,	37,	58,	'2023-04-14 14:59:44',	15000000,	0,	1),
(59,	38,	70,	'2023-04-14 15:15:18',	29900000,	0,	1),
(60,	39,	67,	'2023-04-14 15:18:26',	8790000,	0,	1),
(61,	40,	57,	'2023-04-14 15:18:51',	23890000,	0,	1),
(62,	41,	68,	'2023-04-14 15:19:10',	34000000,	0,	1),
(63,	42,	66,	'2023-04-14 15:25:19',	12990000,	0,	1),
(64,	43,	65,	'2023-04-14 16:44:01',	22990000,	2299000,	1),
(65,	44,	57,	'2023-04-15 04:15:21',	23890000,	4778000,	1),
(66,	44,	56,	'2023-04-15 04:15:21',	23890000,	4778000,	1),
(67,	45,	68,	'2023-04-15 04:20:34',	68000000,	5100000,	2),
(68,	45,	59,	'2023-04-15 04:20:34',	40780000,	3058500,	2),
(69,	46,	66,	'2023-04-15 04:33:18',	12990000,	1948500,	1),
(70,	47,	67,	'2023-04-15 14:29:25',	8790000,	1318500,	1),
(71,	47,	63,	'2023-04-15 14:29:25',	16980000,	1273500,	2),
(72,	48,	63,	'2023-04-15 14:29:26',	16980000,	1273500,	2),
(73,	48,	67,	'2023-04-15 14:29:26',	8790000,	1318500,	1),
(74,	49,	65,	'2023-04-15 14:37:46',	22990000,	3448500,	1),
(75,	49,	67,	'2023-04-15 14:37:46',	8790000,	1318500,	1),
(76,	50,	62,	'2023-04-15 14:41:50',	8490000,	1273500,	1),
(77,	50,	71,	'2023-04-15 14:41:50',	12090000,	1813500,	1),
(78,	51,	59,	'2023-04-15 14:46:39',	20390000,	3058500,	1),
(79,	52,	62,	'2023-04-15 14:47:14',	8490000,	1273500,	1),
(80,	53,	65,	'2023-04-15 14:56:03',	22990000,	3448500,	1),
(81,	53,	71,	'2023-04-15 14:56:03',	12090000,	1813500,	1),
(82,	54,	68,	'2023-04-15 14:56:18',	34000000,	5100000,	1),
(83,	55,	63,	'2023-04-15 14:58:39',	8490000,	1273500,	1),
(84,	55,	67,	'2023-04-15 14:58:39',	8790000,	1318500,	1),
(85,	55,	71,	'2023-04-15 14:58:39',	12090000,	1813500,	1),
(86,	56,	68,	'2023-04-15 15:07:34',	68000000,	5100000,	2),
(87,	57,	66,	'2023-04-15 15:09:45',	25980000,	1948500,	2),
(88,	58,	67,	'2023-04-15 15:13:06',	8790000,	1318500,	1),
(89,	59,	61,	'2023-04-15 15:18:28',	27990000,	4198500,	1),
(90,	60,	59,	'2023-04-15 15:20:38',	20390000,	3058500,	1),
(91,	61,	59,	'2023-04-15 15:21:19',	20390000,	3058500,	1),
(92,	62,	67,	'2023-04-15 15:22:33',	8790000,	1318500,	1),
(93,	63,	70,	'2023-04-15 16:11:20',	89700000,	5980000,	3),
(94,	64,	72,	'2023-04-15 16:19:06',	19900000,	3980000,	1),
(95,	65,	71,	'2023-04-16 04:11:42',	12090000,	1813500,	1),
(96,	65,	59,	'2023-04-16 04:11:42',	20390000,	3058500,	1),
(97,	66,	67,	'2023-04-16 11:22:57',	8790000,	1318500,	1),
(98,	66,	68,	'2023-04-16 11:22:58',	34000000,	5100000,	1),
(99,	67,	59,	'2023-04-16 11:26:04',	20390000,	3058500,	1),
(100,	68,	66,	'2023-04-16 11:35:16',	12990000,	1948500,	1),
(101,	69,	72,	'2023-04-16 11:44:34',	19900000,	3980000,	1),
(102,	70,	57,	'2023-04-16 11:51:51',	23890000,	4778000,	1),
(103,	71,	66,	'2023-04-16 11:59:05',	12990000,	1948500,	1),
(104,	72,	67,	'2023-04-16 12:50:22',	8790000,	1318500,	1),
(105,	72,	59,	'2023-04-16 12:50:22',	20390000,	3058500,	1),
(106,	73,	72,	'2023-04-16 12:52:25',	19900000,	3980000,	1),
(107,	73,	59,	'2023-04-16 12:52:25',	20390000,	3058500,	1),
(108,	73,	71,	'2023-04-16 12:52:25',	12090000,	1813500,	1),
(109,	74,	71,	'2023-04-17 08:36:18',	12090000,	1209000,	1),
(110,	75,	58,	'2023-04-19 14:48:10',	15000000,	3000000,	1),
(111,	76,	67,	'2023-04-19 14:49:09',	26370000,	0,	3),
(112,	77,	67,	'2023-04-20 15:56:01',	17580000,	1758000,	2),
(113,	78,	58,	'2023-04-20 16:23:27',	15000000,	3000000,	1),
(114,	79,	68,	'2023-04-21 10:24:36',	34000000,	6800000,	1),
(115,	80,	65,	'2023-04-21 10:56:38',	22990000,	4598000,	1),
(116,	80,	72,	'2023-04-21 10:56:38',	19900000,	3980000,	1),
(117,	80,	55,	'2023-04-21 10:56:38',	29900000,	5980000,	1),
(118,	81,	59,	'2023-04-21 18:46:40',	20390000,	4078000,	1),
(119,	82,	68,	'2023-04-21 18:47:35',	34000000,	6800000,	1),
(120,	83,	57,	'2023-04-21 18:47:54',	23890000,	4778000,	1),
(121,	84,	62,	'2023-04-21 18:49:29',	8490000,	1698000,	1),
(122,	85,	71,	'2023-04-21 19:32:06',	12090000,	2418000,	1),
(123,	86,	68,	'2023-04-21 19:35:36',	34000000,	6800000,	1),
(124,	87,	71,	'2023-04-21 20:25:39',	12090000,	2418000,	1),
(125,	88,	72,	'2023-04-22 18:40:03',	19900000,	3980000,	1),
(126,	89,	62,	'2023-04-22 18:45:33',	8490000,	1698000,	1),
(127,	90,	59,	'2023-04-22 22:14:31',	40780000,	4078000,	2),
(128,	90,	67,	'2023-04-22 22:14:31',	8790000,	1758000,	1),
(129,	90,	72,	'2023-04-22 22:14:31',	19900000,	3980000,	1),
(130,	90,	68,	'2023-04-22 22:14:31',	102000000,	6800000,	3),
(131,	91,	71,	'2023-04-22 22:34:33',	12090000,	2418000,	1),
(132,	91,	65,	'2023-04-22 22:34:33',	45980000,	4598000,	2),
(133,	92,	58,	'2023-04-22 23:57:10',	15000000,	3000000,	1),
(134,	93,	76,	'2023-04-22 23:57:46',	16800000,	0,	1),
(135,	94,	76,	'2023-04-23 00:07:08',	16800000,	0,	1),
(136,	94,	68,	'2023-04-23 00:07:08',	34000000,	6800000,	1),
(137,	95,	67,	'2023-04-23 00:07:39',	8790000,	0,	1),
(138,	96,	66,	'2023-04-23 00:08:28',	12990000,	2598000,	1),
(139,	97,	76,	'2023-04-23 00:24:00',	16800000,	0,	1),
(140,	98,	57,	'2023-04-23 00:24:31',	23890000,	4778000,	1),
(141,	99,	57,	'2023-04-23 00:24:56',	23890000,	4778000,	1),
(142,	100,	58,	'2023-04-23 00:31:52',	15000000,	3000000,	1),
(143,	101,	62,	'2023-04-23 00:32:17',	8490000,	1698000,	1),
(144,	102,	76,	'2023-04-23 10:28:22',	16800000,	0,	1),
(145,	103,	57,	'2023-04-23 10:29:30',	23890000,	4778000,	1),
(146,	104,	57,	'2023-04-23 11:28:27',	23890000,	4778000,	1),
(147,	105,	57,	'2023-04-23 12:29:04',	47780000,	4778000,	2),
(148,	106,	60,	'2023-04-23 22:50:48',	22990000,	0,	1),
(149,	106,	66,	'2023-04-23 22:50:48',	64950000,	2598000,	5),
(150,	106,	61,	'2023-04-23 22:50:48',	139950000,	0,	5),
(151,	107,	62,	'2023-04-23 22:52:20',	8490000,	1698000,	1),
(152,	108,	72,	'2023-04-23 23:05:52',	19900000,	0,	1),
(153,	108,	71,	'2023-04-23 23:05:52',	24180000,	0,	2),
(154,	109,	76,	'2023-04-23 23:08:01',	16800000,	0,	1),
(155,	110,	58,	'2023-04-23 23:08:03',	15000000,	3000000,	1),
(156,	111,	68,	'2023-04-23 23:47:41',	34000000,	6800000,	1),
(157,	112,	68,	'2023-04-24 21:21:23',	68000000,	6800000,	2),
(158,	112,	57,	'2023-04-24 21:21:23',	119450000,	4778000,	5),
(159,	113,	63,	'2023-04-24 21:35:49',	16980000,	1698000,	2),
(160,	113,	67,	'2023-04-24 21:35:49',	17580000,	0,	2),
(161,	113,	71,	'2023-04-24 21:35:49',	24180000,	0,	2),
(162,	114,	58,	'2023-04-24 21:36:33',	15000000,	3000000,	1),
(163,	114,	58,	'2023-04-24 21:36:33',	15000000,	3000000,	1),
(164,	115,	57,	'2023-04-24 22:37:05',	119450000,	4778000,	5),
(165,	115,	63,	'2023-04-24 22:37:05',	8490000,	1698000,	1),
(166,	115,	64,	'2023-04-24 22:37:05',	8490000,	1698000,	1),
(167,	116,	57,	'2023-04-24 22:42:14',	23890000,	4778000,	1),
(168,	116,	82,	'2023-04-24 22:42:14',	14980000,	0,	2),
(169,	116,	56,	'2023-04-24 22:42:14',	47780000,	4778000,	2),
(170,	116,	83,	'2023-04-24 22:42:14',	11990000,	0,	1),
(171,	117,	58,	'2023-04-25 13:29:23',	15000000,	0,	1),
(172,	117,	66,	'2023-04-25 13:29:23',	12990000,	0,	1),
(173,	118,	58,	'2023-04-25 13:30:22',	75000000,	0,	5),
(174,	118,	67,	'2023-04-25 13:30:22',	26370000,	0,	3),
(175,	119,	68,	'2023-04-25 13:31:19',	170000000,	0,	5);

DELIMITER ;;

CREATE TRIGGER `a_i_order_detail` AFTER INSERT ON `order_detail` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'order_detail'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `tg_updateQtyVariantAfterAddToOrderDeId` AFTER INSERT ON `order_detail` FOR EACH ROW
BEGIN
	declare updated  bool default 0;
	CALL  sp_reduceVariantQtyInOrderByOrderId(NEW.order_id, updated);  
    if(updated < 1) then
      SIGNAL SQLSTATE '02000' SET MESSAGE_TEXT = 'Quantity not upated';
    end if;
END;;

CREATE TRIGGER `a_u_order_detail` AFTER UPDATE ON `order_detail` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'order_detail';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_order_detail` AFTER DELETE ON `order_detail` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'order_detail';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `order_status`;
CREATE TABLE `order_status` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(55) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `title` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `order_status` (`id`, `name`, `title`) VALUES
(1,	'Chờ xác nhận',	'Chờ người bán xác nhận đơn hàng'),
(2,	'Đang giao',	'Đang giao hàng'),
(3,	'Hoàn thành',	'Đơn hàng đã được giao thành công'),
(4,	'Đã hủy',	'Đã hủy bởi bạn');

DELIMITER ;;

CREATE TRIGGER `a_i_order_status` AFTER INSERT ON `order_status` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'order_status'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_order_status` AFTER UPDATE ON `order_status` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'order_status';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_order_status` AFTER DELETE ON `order_status` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'order_status';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `orders`;
CREATE TABLE `orders` (
  `id` int NOT NULL AUTO_INCREMENT,
  `user_id` int DEFAULT NULL,
  `created_date` datetime DEFAULT NULL,
  `is_pay` bit(1) DEFAULT NULL,
  `payment_id` int DEFAULT NULL,
  `status` int DEFAULT NULL,
  `is_cancelled` bit(1) DEFAULT NULL,
  `promotion_id` int DEFAULT NULL,
  `district` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `address_line` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `province` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `postal_id` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  KEY `fk_orders_promotion_user_1` (`promotion_id`) USING BTREE,
  KEY `fk_orders_order_status_1` (`status`) USING BTREE,
  KEY `fk_orders_payment_method_1` (`payment_id`) USING BTREE,
  CONSTRAINT `fk_orders_order_status_1` FOREIGN KEY (`status`) REFERENCES `order_status` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_orders_payment_method_1` FOREIGN KEY (`payment_id`) REFERENCES `payment_method` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_orders_promotion_user_1` FOREIGN KEY (`promotion_id`) REFERENCES `promotion_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `orders` (`id`, `user_id`, `created_date`, `is_pay`, `payment_id`, `status`, `is_cancelled`, `promotion_id`, `district`, `address_line`, `province`, `postal_id`) VALUES
(23,	25,	'2023-03-12 00:17:29',	CONV('1', 2, 10) + 0,	2,	2,	NULL,	NULL,	'string',	'string',	'string',	'string'),
(24,	1,	'2023-03-15 17:18:36',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	2,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(25,	1,	'2023-03-17 13:54:38',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(26,	1,	'2023-03-16 13:56:50',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(27,	1,	'2023-03-20 23:23:22',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	2,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(28,	1,	'2023-03-07 14:38:22',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(29,	1,	'2023-03-14 14:39:42',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'161294'),
(30,	1,	'2023-03-14 14:43:06',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'598141'),
(31,	1,	'2023-04-14 14:47:52',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(32,	1,	'2023-04-14 14:49:13',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'411829'),
(33,	1,	'2023-03-14 14:51:13',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'559589'),
(34,	1,	'2023-04-14 14:52:05',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'939053'),
(35,	1,	'2023-04-14 14:53:18',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'602233'),
(36,	1,	'2023-04-14 14:54:52',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(37,	1,	'2023-04-14 14:59:44',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(38,	1,	'2023-04-14 15:15:18',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'773065'),
(39,	1,	'2023-04-14 15:18:26',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'230897'),
(40,	1,	'2023-04-14 15:18:51',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(41,	1,	'2023-04-14 15:19:10',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'963267'),
(42,	1,	'2023-04-14 15:25:19',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'691738'),
(43,	1,	'2023-04-14 16:44:01',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	2,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(44,	1,	'2023-04-15 04:15:21',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	2,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(45,	1,	'2023-04-15 04:20:34',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'638084'),
(46,	1,	'2023-04-15 04:33:17',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	2,	NULL,	'đường, Tân chánh hiệp',	NULL,	'142073'),
(47,	38,	'2023-04-15 14:29:25',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Thị xã Phước Long',	'227 TO 3 Khu 5, Phường Long Phước',	'Tỉnh Bình Phước',	'276865'),
(48,	38,	'2023-04-15 14:29:26',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Thị xã Phước Long',	'227 TO 3 Khu 5, Phường Long Phước',	'Tỉnh Bình Phước',	'276865'),
(49,	38,	'2023-04-15 14:37:46',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Thị xã Phước Long',	'227 TO 3 Khu 5, Phường Long Phước',	'Tỉnh Bình Phước',	'697096'),
(50,	38,	'2023-04-15 14:41:50',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Thị xã Phước Long',	'227 TO 3 Khu 5, Phường Long Phước',	'Tỉnh Bình Phước',	'579615'),
(51,	1,	'2023-04-15 14:46:39',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	2,	NULL,	'đường, Tân chánh hiệp',	NULL,	'647827'),
(52,	1,	'2023-04-15 14:47:14',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'628354'),
(53,	39,	'2023-04-15 14:56:03',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'670685'),
(54,	39,	'2023-04-15 14:56:18',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'851135'),
(55,	39,	'2023-04-15 14:58:39',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'169734'),
(56,	26,	'2023-04-15 15:07:34',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận 12',	'57c dong bac , Phường Tân Chánh Hiệp',	'Thành phố Hồ Chí Minh',	'366774'),
(57,	26,	'2023-04-15 15:09:45',	CONV('1', 2, 10) + 0,	2,	3,	NULL,	NULL,	'Quận Ba Đình',	'123, Phường Trúc Bạch',	'Thành phố Hà Nội',	'346199'),
(58,	26,	'2023-04-15 15:13:06',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'835846'),
(59,	39,	'2023-04-15 15:18:28',	CONV('0', 2, 10) + 0,	3,	2,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'371447'),
(60,	26,	'2023-04-15 15:20:38',	CONV('0', 2, 10) + 0,	3,	2,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'861409'),
(61,	35,	'2023-04-15 15:21:19',	CONV('0', 2, 10) + 0,	3,	2,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'359719'),
(62,	1,	'2023-04-15 15:22:33',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'160635'),
(63,	40,	'2023-04-15 16:11:20',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận Hoàn Kiếm',	'Xóm 9, Phường Phúc Tân',	'Thành phố Hà Nội',	'296549'),
(64,	26,	'2023-04-15 16:19:06',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'471134'),
(65,	39,	'2023-04-16 04:11:42',	CONV('0', 2, 10) + 0,	3,	2,	NULL,	NULL,	'Quận Hoàn Kiếm',	'đường, Tân chánh hiệp',	'Thành phố Hà Nội',	'215750'),
(66,	39,	'2023-04-16 11:22:57',	CONV('0', 2, 10) + 0,	3,	2,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'925368'),
(67,	39,	'2023-04-16 11:26:04',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'684999'),
(68,	39,	'2023-04-16 11:35:16',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'137689'),
(69,	39,	'2023-04-16 11:44:34',	CONV('0', 2, 10) + 0,	3,	2,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'379463'),
(70,	39,	'2023-04-16 11:51:51',	CONV('0', 2, 10) + 0,	3,	2,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'683910'),
(71,	39,	'2023-04-16 11:59:05',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'820561'),
(72,	1,	'2023-04-16 12:50:22',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(73,	39,	'2023-04-16 12:52:25',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'905083'),
(74,	36,	'2023-04-17 08:36:18',	CONV('0', 2, 10) + 0,	3,	2,	NULL,	NULL,	'Thị xã Phú Thọ',	'đường, Tân chánh hiệp',	'Tỉnh Phú Thọ',	'356757'),
(75,	1,	'2023-04-19 14:48:10',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(76,	1,	'2023-04-19 14:49:09',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(77,	26,	'2023-04-20 15:56:01',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	NULL,	'đường, Tân chánh hiệp',	NULL,	'815937'),
(78,	1,	'2023-04-20 16:23:27',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(79,	1,	'2023-04-21 10:24:36',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(80,	1,	'2023-04-21 10:56:38',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	'Quận Ba Đình',	'Tân chánh Hiệp, Phường Phúc Xá',	'Thành phố Hà Nội',	'390443'),
(81,	44,	'2023-04-21 18:46:40',	CONV('0', 2, 10) + 0,	2,	4,	NULL,	NULL,	'Huyện Hàm Thuận Nam',	'KDL Ta-Kou, Thị trấn Thuận Nam',	'Tỉnh Bình Thuận',	'101104'),
(82,	44,	'2023-04-21 18:47:35',	CONV('0', 2, 10) + 0,	2,	4,	NULL,	NULL,	'Thành phố Hà Giang',	'28, Phường Quang Trung',	'Tỉnh Hà Giang',	'379321'),
(83,	44,	'2023-04-21 18:47:54',	CONV('1', 2, 10) + 0,	2,	2,	NULL,	NULL,	'Huyện Đồng Văn',	'32, Xã Lũng Cú',	'Tỉnh Hà Giang',	'424385'),
(84,	44,	'2023-04-21 18:49:29',	CONV('1', 2, 10) + 0,	2,	3,	NULL,	NULL,	'Quận Ba Đình',	'32, Phường Phúc Xá',	'Thành phố Hà Nội',	'727033'),
(85,	26,	'2023-04-21 19:32:06',	CONV('0', 2, 10) + 0,	3,	1,	NULL,	NULL,	NULL,	'undefined, undefined',	NULL,	'976003'),
(86,	26,	'2023-04-21 19:35:36',	CONV('0', 2, 10) + 0,	3,	1,	NULL,	NULL,	NULL,	'undefined, undefined',	NULL,	'632627'),
(87,	26,	'2023-04-21 20:25:39',	CONV('0', 2, 10) + 0,	3,	4,	NULL,	NULL,	NULL,	'undefined, undefined',	NULL,	'656881'),
(88,	44,	'2023-04-22 18:40:03',	CONV('0', 2, 10) + 0,	2,	4,	NULL,	NULL,	NULL,	'undefined, undefined',	NULL,	'530833'),
(89,	44,	'2023-04-22 18:45:33',	CONV('0', 2, 10) + 0,	2,	4,	NULL,	NULL,	NULL,	'undefined, undefined',	NULL,	'126815'),
(90,	25,	'2023-04-22 22:14:31',	CONV('1', 2, 10) + 0,	1,	3,	NULL,	NULL,	'Huyện Cái Nước',	'12/12/90 Phạm Ngũ Lão, Xã Hưng Mỹ',	'Tỉnh Cà Mau',	'814771'),
(91,	44,	'2023-04-22 22:34:33',	CONV('0', 2, 10) + 0,	2,	4,	NULL,	NULL,	'Thành phố Hà Giang',	'KM 12345, Phường Quang Trung',	'Tỉnh Hà Giang',	'922046'),
(92,	44,	'2023-04-22 23:57:10',	CONV('0', 2, 10) + 0,	2,	4,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(93,	44,	'2023-04-22 23:57:46',	CONV('0', 2, 10) + 0,	2,	4,	NULL,	NULL,	NULL,	'undefined, undefined',	NULL,	'364343'),
(94,	44,	'2023-04-23 00:07:08',	CONV('0', 2, 10) + 0,	2,	4,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(95,	44,	'2023-04-23 00:07:39',	CONV('0', 2, 10) + 0,	2,	4,	NULL,	NULL,	'',	', ',	'',	'918549'),
(96,	44,	'2023-04-23 00:08:28',	CONV('0', 2, 10) + 0,	2,	4,	NULL,	NULL,	'',	', ',	'',	'196282'),
(97,	44,	'2023-04-23 00:24:00',	CONV('0', 2, 10) + 0,	2,	4,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(98,	44,	'2023-04-23 00:24:31',	CONV('0', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(99,	44,	'2023-04-23 00:24:56',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận Ba Đình',	'123, Phường Phúc Xá',	'Thành phố Hà Nội',	'992869'),
(100,	44,	'2023-04-23 00:31:52',	CONV('0', 2, 10) + 0,	2,	3,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(101,	44,	'2023-04-23 00:32:17',	CONV('0', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(102,	44,	'2023-04-23 10:28:22',	CONV('0', 2, 10) + 0,	2,	3,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(103,	44,	'2023-04-23 10:29:30',	CONV('0', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(104,	44,	'2023-04-23 11:28:27',	CONV('1', 2, 10) + 0,	2,	3,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(105,	44,	'2023-04-23 12:29:04',	CONV('1', 2, 10) + 0,	2,	3,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(106,	45,	'2023-04-23 22:50:48',	CONV('1', 2, 10) + 0,	2,	3,	NULL,	NULL,	'Huyện Quản Bạ',	'12A Hoàng Văn Thụ, Xã Nghĩa Thuận',	'Tỉnh Hà Giang',	'839895'),
(107,	44,	'2023-04-23 22:52:20',	CONV('1', 2, 10) + 0,	2,	3,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(108,	45,	'2023-04-23 23:05:52',	CONV('0', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận 1',	'12A Đa Kao, Phường Phạm Ngũ Lão',	'Thành phố Hồ Chí Minh',	'300536'),
(109,	45,	'2023-04-23 23:08:01',	CONV('1', 2, 10) + 0,	2,	3,	NULL,	NULL,	'Quận 1',	'12A Đa Kao, Phường Phạm Ngũ Lão',	'Thành phố Hồ Chí Minh',	'300536'),
(110,	44,	'2023-04-23 23:08:03',	CONV('1', 2, 10) + 0,	2,	3,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(111,	44,	'2023-04-23 23:47:41',	CONV('1', 2, 10) + 0,	2,	2,	NULL,	NULL,	'Thành phố Lào Cai',	'123, Phường Duyên Hải',	'Tỉnh Lào Cai',	'616654'),
(112,	41,	'2023-04-24 21:21:23',	CONV('1', 2, 10) + 0,	1,	1,	NULL,	NULL,	'Quận Ba Đình',	'a3 , Phường Trúc Bạch',	'Thành phố Hà Nội',	'118380'),
(113,	26,	'2023-04-24 21:35:49',	CONV('0', 2, 10) + 0,	3,	1,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(114,	26,	'2023-04-24 21:36:33',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(115,	25,	'2023-04-24 22:37:05',	CONV('1', 2, 10) + 0,	2,	3,	NULL,	31,	'Quận 11',	'123A Nguyễn Thiện Thuật, Phường 02',	'Thành phố Hồ Chí Minh',	'457726'),
(116,	25,	'2023-04-24 22:42:14',	CONV('1', 2, 10) + 0,	2,	3,	NULL,	NULL,	'Quận 11',	'123A Nguyễn Thiện Thuật, Phường 02',	'Thành phố Hồ Chí Minh',	'457726'),
(117,	26,	'2023-04-25 13:29:23',	CONV('1', 2, 10) + 0,	1,	2,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(118,	26,	'2023-04-26 13:30:22',	CONV('1', 2, 10) + 0,	1,	3,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000'),
(119,	26,	'2023-04-27 13:31:19',	CONV('1', 2, 10) + 0,	3,	3,	NULL,	NULL,	'Quận 12',	'đường, Tân chánh hiệp',	'Hồ Chí Minh',	'00000000');

DELIMITER ;;

CREATE TRIGGER `a_i_orders` AFTER INSERT ON `orders` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'orders'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_orders` AFTER UPDATE ON `orders` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'orders';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_orders` AFTER DELETE ON `orders` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'orders';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `payment_method`;
CREATE TABLE `payment_method` (
  `id` int NOT NULL AUTO_INCREMENT,
  `method` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `payment_method` (`id`, `method`) VALUES
(1,	'VISA_CARD'),
(2,	'MOMO'),
(3,	'CASH');

DELIMITER ;;

CREATE TRIGGER `a_i_payment_method` AFTER INSERT ON `payment_method` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'payment_method'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_payment_method` AFTER UPDATE ON `payment_method` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'payment_method';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_payment_method` AFTER DELETE ON `payment_method` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'payment_method';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `product`;
CREATE TABLE `product` (
  `id` int NOT NULL AUTO_INCREMENT,
  `product_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `description` varchar(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `create_date` datetime DEFAULT NULL,
  `update_date` datetime DEFAULT NULL,
  `category_id` int DEFAULT NULL,
  `is_delete` bit(1) DEFAULT NULL,
  `brand_id` int DEFAULT NULL,
  `promotion_id` int DEFAULT NULL,
  `type` int DEFAULT NULL,
  `image` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  KEY `fk_product_category_1` (`category_id`) USING BTREE,
  KEY `fk_product_brand_1` (`brand_id`) USING BTREE,
  KEY `fk_promotion_product_product_1` (`promotion_id`) USING BTREE,
  CONSTRAINT `fk_product_brand_1` FOREIGN KEY (`brand_id`) REFERENCES `brand` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_product_category_1` FOREIGN KEY (`category_id`) REFERENCES `category` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_promotion_product_product_1` FOREIGN KEY (`promotion_id`) REFERENCES `promotion_product` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `product` (`id`, `product_name`, `description`, `create_date`, `update_date`, `category_id`, `is_delete`, `brand_id`, `promotion_id`, `type`, `image`) VALUES
(93,	'Iphone 14 promax',	'iPhone 14 Pro Max là mẫu flagship nổi bật nhất của Apple trong lần trở lại năm 2022 với nhiều cải tiến về công nghệ cũng như vẻ ngoài cao cấp, sang chảnh hợp với gu thẩm mỹ đại chúng. Những chiếc điện thoại đến từ nhà Táo Khuyết nhận được rất nhiều sự kỳ vọng của thị trường ngay từ khi chưa ra mắt. Vậy liệu những chiếc flagship đến từ công ty công nghệ hàng đầu thế giới này có làm bạn thất vọng? Cùng khám phá những điều thú vị về iPhone 14 Pro Max ở bài viết dưới đây nhé.',	'2023-04-08 08:15:15',	'2023-04-18 17:42:08',	4,	CONV('0', 2, 10) + 0,	2,	18,	NULL,	'product-93.png'),
(94,	'Samsung S20 Ultra',	'Samsung Galaxy S20 là chiếc điện thoại với thiết kế màn hình tràn viền không khuyết điểm, camera sau ấn tượng, hiệu năng khủng cùng nhiều những đột phá công nghệ nổi bật, dẫn đầu thế giới.\n',	'2023-04-08 08:18:06',	'2023-04-08 08:18:06',	6,	CONV('0', 2, 10) + 0,	1,	19,	1,	'product-94.png'),
(95,	'Samsung Galaxy S23 Ultra',	'Samsung Galaxy S23 Ultra là điện thoại cao cấp của hãng điện thoại Samsung được ra mắt vào đầu năm 2023. Điện thoại Samsung S23 series mới này sở hữu camera độ phân giải 200MP ấn tượng cùng một khung viền vuông vức sang trọng. Cấu hình máy cũng là một điểm nổi bật với con chip Snapdragon 8 Gen 2 mạnh mẽ, bộ nhớ RAM 8GB mang lại hiệu suất xử lý vượt trội.',	'2023-04-08 09:40:55',	'2023-04-08 09:40:55',	6,	CONV('0', 2, 10) + 0,	1,	18,	1,	'product-95.png'),
(96,	'Samsung Galaxy A34 5G',	'Galaxy A34 5G sở hữu thiết kế đẹp và hiện đại với mặt lưng nhẵn làm từ nhựa cao cấp, màn hình lớn và cụm camera được bố trí theo một hàng dọc bắt mắt. Do sở hữu thiết kế từ nhựa nên máy sẽ có trọng lượng nhẹ hơn giúp mang lại cảm giác cầm nắm nhẹ nhàng.',	'2023-04-09 07:46:54',	'2023-04-09 07:52:19',	6,	CONV('0', 2, 10) + 0,	1,	19,	1,	'product-96.png'),
(97,	'Laptop Apple MacBook Air M1 2020',	'Chiếc MacBook này được trang bị con chip Apple M1 được sản xuất độc quyền bởi Nhà Táo trên tiến trình 5 nm, 8 lõi bao gồm 4 lõi tiết kiệm điện và 4 lõi hiệu suất cao, mang đến một hiệu năng kinh ngạc, xử lý mọi tác vụ văn phòng một cách mượt mà như Word, Excel, Powerpoint,... thực hiện tốt các nhiệm vụ chỉnh sửa hình ảnh, kết xuất 2D trên các phần mềm Photoshop, AI,... máy còn hỗ trợ tiết kiệm được điện năng cao.',	'2023-04-09 07:51:20',	'2023-04-09 07:51:20',	8,	CONV('0', 2, 10) + 0,	2,	18,	1,	'product-97.png'),
(98,	'Samsung Galaxy S21 FE 5G',	'Galaxy S21 FE 5G thiết kế mỏng nhẹ với độ dày 7.9 mm, khối lượng chỉ 177 gram, các góc cạnh bo tròn cho cảm giác hài hòa, mềm mại, kết hợp các tông màu thời thượng gồm tím, xanh lá, xám và trắng giúp bạn dễ dàng tạo nên phong cách riêng đầy cá tính.',	'2023-04-09 07:54:06',	'2023-04-09 15:14:51',	6,	CONV('0', 2, 10) + 0,	1,	19,	NULL,	'product-98.png'),
(99,	'Samsung Galaxy S20 FE',	'Camera trên S20 FE là 3 cảm biến chất lượng nằm gọn trong mô đun chữ nhật độc đáo ở mặt lưng bao gồm: Camera chính 12 MP cho chất lượng ảnh sắc nét, camera góc siêu rộng 12 MP cung cấp góc chụp tối đa và cuối cùng camera tele 8 MP hỗ trợ zoom quang học 3X.',	'2023-04-09 07:57:59',	'2023-04-17 09:58:56',	6,	CONV('0', 2, 10) + 0,	1,	18,	NULL,	'product-99.png'),
(100,	'Iphone 14',	'iPhone 14 128GB được xem là mẫu smartphone bùng nổ của nhà táo trong năm 2022, ấn tượng với ngoại hình trẻ trung, màn hình chất lượng đi kèm với những cải tiến về hệ điều hành và thuật toán xử lý hình ảnh, giúp máy trở thành cái tên thu hút được đông đảo người dùng quan tâm tại thời điểm ra mắt.',	'2023-04-09 08:00:07',	'2023-04-09 08:00:07',	4,	CONV('0', 2, 10) + 0,	2,	19,	NULL,	'product-100.png'),
(104,	'Iphone 11',	'iPhone 11 sở hữu hiệu năng khá mạnh mẽ, ổn định trong thời gian dài nhờ được trang bị chipset A13 Bionic. Màn hình LCD 6.1 inch sắc nét cùng chất lượng hiển thị Full HD của máy cho trải nghiệm hình ảnh mượt mà và có độ tương phản cao. Hệ thống camera hiện đại được tích hợp những tính năng công nghệ mới kết hợp với viên Pin dung lượng 3110mAh, giúp nâng cao trải nghiệm của người dùng.',	'2023-04-09 20:09:06',	'2023-04-09 20:09:06',	4,	CONV('0', 2, 10) + 0,	2,	18,	NULL,	'product-104.png'),
(105,	'Apple Macbook Air M2 2022',	'Thiết kế sang trọng, lịch lãm - siêu mỏng 11.3mm, chỉ 1.24kg\nHiệu năng hàng đầu - Chip Apple m2, 8 nhân GPU, hỗ trợ tốt các phần mềm như Word, Axel, Adoble Premier\nĐa nhiệm mượt mà - Ram 16GB, SSD 256GB cho phép vừa làm việc, vừa nghe nhạc\nMàn hình sắc nét - Độ phân giải 2560 x 1664 cùng độ sáng 500 nits\nÂm thanh sống động - 4 loa tramg bị công nghệ dolby atmos và âm thanh đa chiều',	'2023-04-09 13:21:47',	'2023-04-09 13:21:47',	8,	CONV('0', 2, 10) + 0,	2,	19,	NULL,	'product-105.png'),
(109,	'OPPO Find N2 Flip',	'OPPO Find N2 Flip, chiếc điện thoại gập đầu tiên của OPPO được giới thiệu chính thức vào tháng 03/2023. Với cấu hình mạnh mẽ bao gồm con chip Dimensity 9000+ và bộ camera nổi trội, đây được xem là một trong những mẫu điện thoại đáng chú ý ở thời điểm hiện tại khi sở hữu bộ cấu hình tốt trong tầm giá.',	'2023-04-15 03:15:22',	'2023-04-15 03:15:22',	6,	CONV('0', 2, 10) + 0,	77,	1,	1,	'product-109.png'),
(110,	'Iphone 15',	'Đẹp quá',	'2023-04-15 16:14:57',	'2023-04-15 16:14:57',	4,	CONV('0', 2, 10) + 0,	2,	NULL,	NULL,	'product-110.png'),
(111,	'Apple Macbook Pro 13 M2 2022',	'Sau sự thành công của Macbook Pro M1, Apple tiếp tục cho ra mắt phiên bản nâng cấp với con chip mạnh hơn mang tên Macbook Pro M2 vào năm 2022. Macbook Pro M2 2022 sở hữu một hiệu năng vượt trội với con chip M2, card đồ họa 10 nhân GPU hứa hẹn mang lại cho người dùng những trải nghiệm vượt trội.',	'2023-04-18 17:08:53',	'2023-04-18 17:08:53',	8,	CONV('0', 2, 10) + 0,	2,	1,	NULL,	'product-111.png'),
(117,	'Laptop Lenovo ThinkBook 14s',	'Lenovo ThinkBook 14s G2 ITL i5 (20VA000NVN) là chiếc laptop học tập - văn phòng phù hợp với học sinh, sinh viên hay người làm văn phòng cần một chiếc máy tính mỏng nhẹ nhưng vẫn có cấu hình ổn định.',	'2023-04-22 21:05:28',	'2023-04-22 21:05:28',	7,	CONV('0', 2, 10) + 0,	82,	2,	NULL,	'product-117.png'),
(118,	'Laptop Lenovo Ideapad 3',	'Kích thước màn hình 15.6 inch với độ phân giải Full HD giúp các chi tiết hiển thị trên màn hình được rõ ràng, sắc nét. Tấm nền TN cho tốc độ phản hồi nhanh chóng hơn, đồng thời hạn chế tối đa hiện tượng nhức mỏi mắt nhờ công nghệ chống chói Anti Glare. ',	'2023-04-22 21:18:12',	'2023-04-22 21:18:12',	8,	CONV('0', 2, 10) + 0,	82,	1,	NULL,	'product-118.png'),
(119,	'Laptop Lenovo ThinkPad X1',	'Laptop Lenovo ThinkPad được trang bị bộ vi xử lý Intel Core i7 1260P sở hữu kiến trúc Hybrid khi kết hợp các lõi hiệu năng P-core và các lõi tiết kiệm điện E-core, đi cùng card tích hợp Intel Iris Xe hỗ trợ mình giải quyết mọi nhu cầu trong công việc trên các phần mềm doanh nghiệp hay hoàn thành những bản thiết kế đồ họa trên Photoshop, Illustrator,... thậm chí còn có thể chiến game mượt mà.',	'2023-04-22 21:21:11',	'2023-04-22 21:21:11',	8,	CONV('0', 2, 10) + 0,	82,	2,	NULL,	'product-119.png'),
(120,	'Laptop HP Gaming Victus ',	'Siêu phẩm laptop Gaming đến từ nhà HP với kích thước 15.6 inch, độ phân giải Full HD đi kèm tần số quét lên đến 144Hz hạn chế giật, xé hình, cho tốc độ mượt mà thao tác mướt mắt.\nMáy trang bị CPU Intel Core i5-12450H cùng card đồ họa NVIDIA GeForce GTX 1650 cân mọi tựa game phổ biến hiện nay hay dễ dàng thiết kế, sáng tạo trên Photoshop, Canva, Figma,...\nRAM 8GB đa nhiệm cho mọi thao tác mượt mà, mở nhiều tab cùng lúc mà không lo lag, giật. Ổ cứng 512GB PCIE cho không gian lưu trữ rộng rãi, tải game hay lưu trữ dữ liệu học tập, làm việc thoải mái.\nTrang bị đầy đủ cổng kết nối như: Ethernet, HDMI 2.1, USB-A, Type-C,... hỗ trợ kết nối, truyền tải dữ liệu nhanh chóng.\nLaptop đi kèm đèn bàn phím hỗ trợ game thủ thao tác nhanh gọn trong môi trường thiếu sáng.\n',	'2023-04-23 12:54:53',	'2023-04-23 12:54:53',	7,	CONV('0', 2, 10) + 0,	78,	1,	NULL,	'product-120.png'),
(121,	'Laptop Lenovo Gaming Legion 5',	'Laptop Lenovo Gaming Legion 5 15ARH7 82RE002VVN - Tối ưu trải nghiệm với hiệu suất cực cao\nDù là mẫu laptop gaming nhưng với vẻ bề ngoài trang nhã, laptop Lenovo Gaming Legion 5 15ARH7 82RE002VVN còn rất phù hợp để sử dụng trong môi trường công sở. Với hiệu năng mạnh mẽ của mình, sản phẩm laptop Lenovo Gaming hứa hẹn sẽ làm hài lòng cả những yêu cầu khắt khe nhất dù là công việc hay giải trí.',	'2023-04-23 15:44:06',	'2023-04-25 21:23:02',	7,	CONV('0', 2, 10) + 0,	82,	2,	NULL,	'product-121.png'),
(122,	'OPPO Reno7 Z 5G',	'OPPO đã trình làng mẫu Reno7 Z 5G với thiết kế OPPO Glow độc quyền, camera mang hiệu ứng như máy DSLR chuyên nghiệp cùng viền sáng kép, máy có một cấu hình mạnh mẽ và đạt chứng nhận xếp hạng A về độ mượt.',	'2023-04-24 16:51:37',	'2023-04-24 16:51:37',	6,	CONV('0', 2, 10) + 0,	77,	1,	NULL,	'product-122.png'),
(123,	'Laptop Lenovo Ideapad Gaming 3',	'Laptop Lenovo IdeaPad Gaming 3 15IHU6 82K101B5VN - Chuyên dụng cho cả gaming lẫn đồ họa\nDù là nhu cầu giải trí với những tựa game đình đám cấu hình nặng, hay làm việc trên bộ phần mềm đồ họa chuyên sâu, laptop Lenovo IdeaPad Gaming 3 15IHU6 82K101B5VN đáp ứng trọn vẹn cả hai nhu cầu trên với trải nghiệm sử dụng tuyệt vời mà người dùng laptop tìm kiếm.',	'2023-04-24 20:47:33',	'2023-04-24 20:47:33',	8,	CONV('0', 2, 10) + 0,	82,	2,	NULL,	'product-123.png'),
(124,	'Điện thoại OPPO A77s ',	'OPPO vừa cho ra mắt mẫu điện thoại tầm trung mới với tên gọi OPPO A77s, máy sở hữu màn hình lớn, thiết kế đẹp mắt, hiệu năng ổn định cùng khả năng mở rộng RAM lên đến 8 GB vô cùng nổi bật trong phân khúc.',	'2023-04-24 21:29:09',	'2023-04-24 21:29:09',	6,	CONV('0', 2, 10) + 0,	77,	1,	NULL,	'product-124.png');

DELIMITER ;;

CREATE TRIGGER `a_i_product` AFTER INSERT ON `product` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'product'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_product` AFTER UPDATE ON `product` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'product';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_product` AFTER DELETE ON `product` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'product';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `product_attribute`;
CREATE TABLE `product_attribute` (
  `id` int NOT NULL AUTO_INCREMENT,
  `attribute_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `attribute_value` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `product_id` int DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  KEY `fk_product_attribute_product` (`product_id`) USING BTREE,
  CONSTRAINT `fk_product_attribute_product` FOREIGN KEY (`product_id`) REFERENCES `product` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `product_attribute` (`id`, `attribute_name`, `attribute_value`, `product_id`) VALUES
(114,	'Pin',	'3850',	93),
(115,	'Màn hình',	'Retina',	95),
(116,	'Kích thước màn hình',	'6.1 inches',	95),
(117,	'Camera sau',	'Camera kép 12MP: - Camera góc rộng: ƒ/1.8 aperture - Camera siêu rộng: ƒ/2.4 aperture',	95),
(118,	'Pin',	'4750',	94),
(119,	'Loại card đồ họa',	'8 nhân GPU, 16 nhân Neural Engine',	105),
(120,	'Dung lượng RAM',	'16GB',	105),
(121,	'Công nghệ màn hình',	'Liquid Retina Display',	105),
(122,	'Ram',	'64GB',	110),
(123,	'Màn Hình',	'15inhc',	110),
(124,	'Tần số quét',	'120HZ',	93),
(125,	'Pin ',	'3000',	98),
(126,	'CPU',	'i5, 1135G, 72.4GHz',	117),
(130,	'Màn hình',	'Super AMOLED6.6\"Full HD+',	98),
(131,	'Hệ điều hành',	'Android 13',	98),
(132,	'Camera sau',	'Chính 48 MP &amp; Phụ 8 MP, 5 MP',	98),
(133,	'Camera trước',	'13 MP',	98),
(134,	'Chip',	'MediaTek Dimensity 1080 8 nhân',	98),
(135,	'RAM',	'8 GB',	98),
(136,	'Dung lượng lưu trữ',	'256 GB',	98),
(137,	'SIM',	'2 Nano SIMHỗ trợ 5G',	98),
(138,	'Pin, Sạc',	'5000 mAh25 W',	98),
(139,	'Màn hình',	'Super AMOLED6.6\"Full HD+',	96),
(140,	'Hệ điều hành',	'Android 13',	96),
(141,	'Camera sau',	'Chính 48 MP & Phụ 8 MP, 5 MP',	96),
(142,	'Camera trước',	'13 MP',	96),
(143,	'Chip',	'MediaTek Dimensity 1080 8 nhân',	96),
(144,	'RAM',	'8 GB',	96),
(145,	'Dung lượng lưu trữ',	'256 GB',	96),
(146,	'SIM',	'2 Nano SIMHỗ trợ 5G',	96),
(147,	'Pin, Sạc',	'5000 mAh25 W',	96),
(148,	'CPU:',	'i71260P2.1GHz',	118),
(149,	'RAM:',	'16 GBLPDDR5 (Onboard)5200 MHz',	118),
(150,	'Ổ cứng:',	'512 GB SSD NVMe PCIe (Có thể tháo ra, lắp thanh khác tối đa 2 TB)',	118),
(151,	'Màn hình:',	'14\"WUXGA (1920 x 1200)',	118),
(152,	'Card màn hình:',	'Card tích hợpIntel Iris Xe',	118),
(153,	'Cổng kết nối:',	'0',	118),
(154,	'Đặc biệt:',	'Có màn hình cảm ứngCó đèn bàn phím',	118),
(155,	'Hệ điều hành:',	'Windows 11 Home SL',	118),
(156,	'Thiết kế:',	'Mặt trên Sợi Carbon - Mặt dưới nhôm',	118),
(157,	'Kích thước, khối lượng:',	'Dài 315.6 mm - Rộng 222.5 mm - Dày 15.36 mm - Nặng 1.12 kg',	118),
(158,	'Thời điểm ra mắt:',	'2022',	118),
(159,	'CPU:',	'i71260P2.1GHz',	119),
(160,	'RAM:',	'16 GBLPDDR5 (Onboard)5200 MHz',	119),
(161,	'Ổ cứng:',	'512 GB SSD NVMe PCIe (Có thể tháo ra, lắp thanh khác tối đa 2 TB)',	119),
(162,	'Màn hình:',	'14\"WUXGA (1920 x 1200)',	119),
(163,	'Card màn hình:',	'Card tích hợpIntel Iris Xe',	119),
(164,	'Màn hình:',	'14\"WUXGA (1920 x 1200)',	119),
(165,	'Đặc biệt:',	'Có màn hình cảm ứngCó đèn bàn phím',	119),
(166,	'Hệ điều hành:',	'Windows 11 Home SL',	119),
(167,	'Thiết kế:',	'Mặt trên Sợi Carbon - Mặt dưới nhôm',	119),
(168,	'Kích thước, khối lượng:',	'Dài 315.6 mm - Rộng 222.5 mm - Dày 15.36 mm - Nặng 1.12 kg',	119),
(169,	'Thời điểm ra mắt:',	'2022',	119),
(170,	'CPU:',	'Apple M2100GB/s',	111),
(171,	'RAM:',	'16 GB',	111),
(172,	'Ổ cứng:',	'512 GB SSD',	111),
(173,	'Màn hình:',	'13.3\"Retina (2560 x 1600)',	111),
(174,	'Card màn hình:',	'Card tích hợp10 nhân GPU',	111),
(175,	'Cổng kết nối:',	'Jack tai nghe 3.5 mm2 x Thunderbolt 3',	111),
(176,	'Đặc biệt:',	'Có đèn bàn phím',	111),
(177,	'Hệ điều hành:',	'Mac OS',	111),
(178,	'Thiết kế:',	'Vỏ kim loại',	111),
(179,	'Kích thước, khối lượng:',	'Dài 304.1 mm - Rộng 212.4 mm - Dày 15.6 mm - Nặng 1.4 kg',	111),
(180,	'Thời điểm ra mắt:',	'06/2022',	111),
(181,	'Kích thước, khối lượng:',	'Dài 322 mm - Rộng 207 mm - Dày 14.9 mm - Nặng 1.27 kg',	117),
(182,	'Thời điểm ra mắt:',	'2020',	117),
(183,	'CPU:',	'Apple M2100GB/s',	111),
(184,	'RAM:',	'16 GB',	111),
(185,	'Ổ cứng:',	'512 GB SSD',	111),
(186,	'Màn hình:',	'13.3\"Retina (2560 x 1600)',	111),
(187,	'Card màn hình:',	'Card tích hợp10 nhân GPU',	111),
(188,	'Cổng kết nối:',	'Jack tai nghe 3.5 mm2 x Thunderbolt 3',	111),
(189,	'Đặc biệt:',	'Có đèn bàn phím',	111),
(190,	'Hệ điều hành:',	'Mac OS',	111),
(191,	'Thiết kế:',	'Vỏ kim loại',	111),
(192,	'Kích thước, khối lượng:',	'Dài 304.1 mm - Rộng 212.4 mm - Dày 15.6 mm - Nặng 1.4 kg',	111),
(193,	'Thời điểm ra mắt:',	'06/2022',	111),
(194,	'Màn hình:',	'Super AMOLED6.5\"Full HD+',	99),
(195,	'Hệ điều hành:',	'Android 12',	99),
(196,	'Camera sau:',	'Chính 12 MP & Phụ 12 MP, 8 MP',	99),
(197,	'Camera trước:',	'32 MP',	99),
(198,	'Chip:',	'Snapdragon 865',	99),
(199,	'RAM:',	'8 GB',	99),
(200,	'Dung lượng lưu trữ:',	'256 GB',	99),
(201,	'SIM:',	'2 Nano SIM (SIM 2 chung khe thẻ nhớ)Hỗ trợ 4G',	99),
(202,	'Pin, Sạc:',	'4500 mAh25 W',	99),
(203,	'Màn hình:',	'Super AMOLED6.5\"Full HD+',	99),
(204,	'Hệ điều hành:',	'Android 12',	99),
(205,	'Camera sau:',	'Chính 12 MP & Phụ 12 MP, 8 MP',	99),
(206,	'Camera trước:',	'32 MP',	99),
(207,	'Chip:',	'Snapdragon 865',	99),
(208,	'RAM:',	'8 GB',	99),
(209,	'Dung lượng lưu trữ:',	'256 GB',	99),
(210,	'SIM:',	'2 Nano SIM (SIM 2 chung khe thẻ nhớ)Hỗ trợ 4G',	99),
(211,	'Pin, Sạc:',	'4500 mAh25 W',	99),
(212,	'Màn hình:',	'OLED6.1\"Super Retina XDR',	100),
(213,	'Hệ điều hành:',	'iOS 16',	100),
(214,	'Camera sau:',	'2 camera 12 MP',	100),
(215,	'Camera trước:',	'12 MP',	100),
(216,	'Chip:',	'Apple A15 Bionic',	100),
(217,	'RAM:',	'6 GB',	100),
(218,	'Dung lượng lưu trữ:',	'256 GB',	100),
(219,	'SIM:',	'1 Nano SIM & 1 eSIMHỗ trợ 5G',	100),
(220,	'Pin, Sạc:',	'3279 mAh20 W',	100),
(221,	'Màn hình:',	'AMOLEDChính 6.8\" & Phụ 3.26\"Full HD+',	109),
(222,	'Hệ điều hành:',	'Android 13',	109),
(223,	'Camera sau:',	'Chính 50 MP & Phụ 8 MP',	109),
(224,	'Camera trước:',	'32 MP',	109),
(225,	'Chip:',	'MediaTek Dimensity 9000+ 8 nhân',	109),
(226,	'RAM:',	'8 GB',	109),
(227,	'Dung lượng lưu trữ:',	'256 GB',	109),
(228,	'SIM:',	'2 Nano SIMHỗ trợ 5G',	109),
(229,	'Pin, Sạc:',	'4300 mAh44 W',	109),
(230,	'Màn hình:',	'IPS LCD6.1\"Liquid Retina',	104),
(231,	'Hệ điều hành:',	'iOS 15',	104),
(232,	'Camera sau:',	'2 camera 12 MP',	104),
(233,	'Camera trước:',	'12 MP',	104),
(234,	'Chip:',	'Apple A13 Bionic',	104),
(235,	'RAM:',	'4 GB',	104),
(236,	'Dung lượng lưu trữ:',	'64 GB',	104),
(237,	'SIM:',	'1 Nano SIM & 1 eSIMHỗ trợ 4G',	104),
(238,	'Pin, Sạc:',	'3110 mAh18 W',	104),
(240,	'CPU:',	'Apple M1',	97),
(241,	'RAM:',	'8 GB',	97),
(242,	'Ổ cứng:',	'256 GB SSD',	97),
(243,	'Màn hình:',	'13.3\"Retina (2560 x 1600)',	97),
(244,	'Card màn hình:',	'Card tích hợp7 nhân GPU',	97),
(245,	'Đặc biệt:',	'Có đèn bàn phím',	97),
(246,	'Hệ điều hành:',	'Mac OS',	97),
(247,	'Thiết kế:',	'Vỏ kim loại nguyên khối',	97),
(248,	'Kích thước, khối lượng:',	'Dài 304.1 mm - Rộng 212.4 mm - Dày 4.1 mm đến 16.1 mm - Nặng 1.29 kg',	97),
(249,	'Thời điểm ra mắt:',	'2020',	97),
(300,	'Cổng kết nối:',	'Jack tai nghe 3.5 mm2 x Thunderbolt 3 (USB-C)',	97),
(302,	'Màn hình:',	'AMOLEDChính 6.8\" & Phụ 3.26\"Full HD+',	95),
(303,	'Hệ điều hành:',	'Android 13',	95),
(304,	'Camera sau:',	'Chính 50 MP & Phụ 8 MP',	95),
(305,	'Chip:',	'MediaTek Dimensity 9000+ 8 nhân',	95),
(306,	'RAM:',	'8 GB',	95),
(307,	'Dung lượng lưu trữ:',	'256 GB',	95),
(308,	'SIM:',	'2 Nano SIMHỗ trợ 5G',	95),
(309,	'Pin, Sạc:',	'4300 mAh44 W',	95),
(310,	'Camera trước:',	'32 MP',	95),
(311,	'Ram',	'8',	121),
(312,	'SSD',	'512gb',	121),
(313,	'Màn Hình',	'15.6 inch',	121),
(320,	'Màn hình:',	'AMOLEDChính 6.8\" & Phụ 3.26\"Full HD+',	122),
(323,	'Hệ điều hành:',	'Android 13',	122),
(324,	'Camera sau:',	'Chính 50 MP & Phụ 8 MP',	122),
(325,	'Chip:',	'MediaTek Dimensity 9000+ 8 nhân',	122),
(326,	'RAM:',	'8 GB',	122),
(327,	'Dung lượng lưu trữ:',	'256 GB',	122),
(328,	'SIM:',	'2 Nano SIMHỗ trợ 5G',	122),
(329,	'Pin, Sạc:',	'4300 mAh44 W',	122),
(330,	'Camera trước:',	'32 MP',	122),
(331,	'Pin',	'3000',	124),
(335,	'CPU',	'Snap',	124),
(337,	'Tần số quét',	'120HZ',	124);

DELIMITER ;;

CREATE TRIGGER `a_i_product_attribute` AFTER INSERT ON `product_attribute` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'product_attribute'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_product_attribute` AFTER UPDATE ON `product_attribute` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'product_attribute';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_product_attribute` AFTER DELETE ON `product_attribute` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'product_attribute';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `product_variant`;
CREATE TABLE `product_variant` (
  `id` int NOT NULL AUTO_INCREMENT,
  `sku_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `quantity` int DEFAULT NULL,
  `price` double DEFAULT NULL,
  `status` bit(1) DEFAULT NULL,
  `product_id` int DEFAULT NULL,
  `image` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `display_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `color_id` int DEFAULT NULL,
  `storage_id` int DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `product_id` (`product_id`,`color_id`,`storage_id`) USING BTREE,
  KEY `fk_product_variant_product_1` (`product_id`) USING BTREE,
  KEY `fk_color_product` (`color_id`) USING BTREE,
  KEY `fk_storage_product` (`storage_id`) USING BTREE,
  CONSTRAINT `fk_color_product` FOREIGN KEY (`color_id`) REFERENCES `color` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_product_variant_product_1` FOREIGN KEY (`product_id`) REFERENCES `product` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_storage_product` FOREIGN KEY (`storage_id`) REFERENCES `storage` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `product_variant` (`id`, `sku_name`, `quantity`, `price`, `status`, `product_id`, `image`, `display_name`, `color_id`, `storage_id`) VALUES
(55,	'IP14PRM',	0,	29900000,	CONV('1', 2, 10) + 0,	93,	'productVariant-55',	'Iphone 14 promax yellow',	5,	2),
(56,	'SSU23P',	-1,	23890000,	CONV('1', 2, 10) + 0,	95,	'productVariant-56',	'Samsung Galaxy S23 Ultra 256GB',	4,	3),
(57,	'SSU23W',	24,	23890000,	CONV('1', 2, 10) + 0,	95,	'productVariant-57',	'Samsung Galaxy S23 Ultra 256GB',	2,	3),
(58,	'SSU20B',	2,	15000000,	CONV('1', 2, 10) + 0,	94,	'productVariant-58',	'Samsung S20 Ulra 126GB',	1,	2),
(59,	'IP14R',	0,	20390000,	CONV('1', 2, 10) + 0,	100,	'productVariant-59',	'iPhone 14 128GB',	4,	2),
(60,	'IP14R256',	97,	22990000,	CONV('1', 2, 10) + 0,	100,	'productVariant-60',	'iPhone 14 256GB',	4,	3),
(61,	'IP14R256',	95,	27990000,	CONV('1', 2, 10) + 0,	100,	'productVariant-61',	'iPhone 14 256GB',	4,	4),
(62,	'SSA53128',	100,	8490000,	CONV('1', 2, 10) + 0,	96,	'productVariant-62',	'Samsung Galaxy A34 5G 128GB',	1,	2),
(63,	'SSA53G128',	12,	8490000,	CONV('1', 2, 10) + 0,	96,	'productVariant-63',	'Samsung Galaxy A34 5G 128GB',	3,	2),
(64,	'SSAGR53128',	199,	8490000,	CONV('1', 2, 10) + 0,	96,	'productVariant-64',	'Samsung Galaxy A34 5G 128GB',	10,	2),
(65,	'MGND3SA/A',	25,	22990000,	CONV('1', 2, 10) + 0,	97,	'productVariant-65',	'MacBook Air M1 2020 8GB/256GB/7-core GPU (MGND3SA/A)',	5,	3),
(66,	'SS21FEGRE',	12,	12990000,	CONV('1', 2, 10) + 0,	98,	'productVariant-66',	'Samsung Galaxy S21 FE 5G',	7,	2),
(67,	'SS20FEGRE',	16,	8790000,	CONV('1', 2, 10) + 0,	99,	'productVariant-67',	'Samsung Galaxy S20 FE',	7,	2),
(68,	'AM2BAC',	6,	34000000,	CONV('1', 2, 10) + 0,	105,	'productVariant-68',	'Apple Macbook Air M2 2022 16GB 256GB',	10,	2),
(70,	'IP14PRMB',	11,	29900000,	CONV('0', 2, 10) + 0,	93,	'productVariant-70',	'Iphone 14 Pro Max Black',	1,	2),
(71,	'IP11W128GB',	12,	12090000,	CONV('1', 2, 10) + 0,	104,	'productVariant-71',	'iPhone 11 128GB',	2,	2),
(72,	'OOPFF',	9,	19900000,	CONV('1', 2, 10) + 0,	109,	'productVariant-72',	'OPPO Find N2 Flip',	1,	3),
(73,	'SSSS',	0,	25000000,	CONV('1', 2, 10) + 0,	110,	'productVariant-73',	'Iphone 15 màu den',	1,	1),
(75,	'SKU14PRM',	10,	45000000,	NULL,	93,	'productVariant-75',	'Iphone 14 Promax 1TB  Tím',	8,	5),
(76,	'20VA000NVN',	19,	16800000,	CONV('1', 2, 10) + 0,	117,	'productVariant-76',	'Laptop Lenovo ThinkBook 14s G2 ITL i5 1135G7/8GB/512GB/Win10',	2,	3),
(77,	'82RK005LVN',	10,	13890000,	CONV('1', 2, 10) + 0,	118,	'productVariant-77',	'Laptop Lenovo Ideapad 3 15IAU7 i3 1215U/8GB/256GB/Win11',	10,	3),
(78,	'82RE002VVN',	10,	24490000,	CONV('1', 2, 10) + 0,	121,	'productVariant-78',	'Laptop Lenovo Gaming Legion 5 15ARH7 82RE002VVN',	2,	4),
(81,	'OPP5GB',	100,	7490000,	CONV('1', 2, 10) + 0,	122,	'productVariant-81',	'OPPO Reno7 Z 5G',	1,	2),
(82,	'OPP5GS',	44,	7490000,	CONV('1', 2, 10) + 0,	122,	'productVariant-82',	'OPPO Reno7 Z 5G ',	10,	2),
(83,	'OPPO5GPRO',	89,	11990000,	CONV('1', 2, 10) + 0,	122,	'productVariant-83',	'OPPO Reno7 Pro 5G',	3,	3),
(85,	'OPPO5GPRO',	50,	11990000,	CONV('1', 2, 10) + 0,	122,	'productVariant-85',	'OPPO Reno7 Pro 5G',	1,	4),
(86,	'OPPO13',	10,	12000000,	CONV('1', 2, 10) + 0,	124,	'productVariant-86',	'Điện thoại OPPO A77s Black',	1,	3);

DELIMITER ;;

CREATE TRIGGER `a_i_product_variant` AFTER INSERT ON `product_variant` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'product_variant'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_product_variant` AFTER UPDATE ON `product_variant` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'product_variant';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_product_variant` AFTER DELETE ON `product_variant` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'product_variant';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `promotion_product`;
CREATE TABLE `promotion_product` (
  `id` int NOT NULL AUTO_INCREMENT,
  `expiration_date` datetime DEFAULT NULL,
  `created_date` datetime DEFAULT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `updated_date` datetime DEFAULT NULL,
  `maximum_price` double DEFAULT NULL,
  `activate` bit(1) DEFAULT NULL,
  `is_percent` tinyint(1) DEFAULT '1',
  `discount_amount` double DEFAULT '0',
  `discount` double DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `promotion_product` (`id`, `expiration_date`, `created_date`, `name`, `updated_date`, `maximum_price`, `activate`, `is_percent`, `discount_amount`, `discount`) VALUES
(1,	'2023-04-27 00:59:17',	'2023-04-12 12:26:14',	'-12%',	'2023-04-25 10:22:37',	200000,	CONV('1', 2, 10) + 0,	1,	20,	20),
(2,	'2023-04-26 23:59:00',	'2023-04-10 12:26:06',	'-10%',	'2023-04-25 00:00:00',	300000,	CONV('1', 2, 10) + 0,	1,	10,	10),
(3,	'2023-04-17 23:59:07',	'2023-04-10 16:57:58',	'Giảm 50%',	'2023-04-17 00:00:58',	0,	CONV('1', 2, 10) + 0,	1,	50,	50),
(4,	'2023-04-17 23:12:14',	'2023-04-15 09:25:37',	'-15%',	'2023-04-17 09:25:40',	NULL,	CONV('1', 2, 10) + 0,	1,	15,	NULL),
(5,	'2023-04-24 23:58:40',	NULL,	'Giảm 10h ngày 19-4 ',	'2023-04-19 00:00:54',	NULL,	CONV('1', 2, 10) + 0,	1,	20,	NULL),
(14,	'2023-04-23 00:00:00',	'2023-04-16 00:00:00',	'Giảm khuya',	'2023-04-20 00:00:00',	NULL,	CONV('1', 2, 10) + 0,	1,	20,	20),
(15,	'2023-04-18 23:59:00',	'2023-04-14 23:59:00',	'Ngày 18-4 sale -20%',	'2023-04-18 00:00:00',	NULL,	CONV('1', 2, 10) + 0,	1,	20,	20),
(16,	'2023-04-18 23:59:00',	'2023-04-17 01:18:36',	'-30%',	'2023-04-17 00:30:00',	NULL,	CONV('1', 2, 10) + 0,	1,	30,	NULL),
(17,	'2023-04-18 23:59:00',	'2023-03-15 23:59:00',	'Giảm tháng 3',	'2023-03-15 23:59:00',	NULL,	CONV('1', 2, 10) + 0,	1,	20,	20),
(18,	'2023-04-29 21:11:48',	NULL,	'Khuyến mãi lớn',	'2023-04-27 09:11:53',	NULL,	CONV('1', 2, 10) + 0,	1,	0,	23),
(19,	'2023-04-29 21:12:37',	NULL,	'Khuyến mãi to',	'2023-04-25 09:12:47',	NULL,	CONV('1', 2, 10) + 0,	1,	0,	34);

DELIMITER ;;

CREATE TRIGGER `a_i_promotion_product` AFTER INSERT ON `promotion_product` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'promotion_product'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_promotion_product` AFTER UPDATE ON `promotion_product` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'promotion_product';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_promotion_product` AFTER DELETE ON `promotion_product` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'promotion_product';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `promotion_type`;
CREATE TABLE `promotion_type` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name_promotion_type` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `condition_minimum` int DEFAULT NULL,
  `amount` double DEFAULT NULL,
  `is_limited` bit(1) DEFAULT NULL,
  `descriptions` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `limited_amount` int DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `promotion_type` (`id`, `name_promotion_type`, `condition_minimum`, `amount`, `is_limited`, `descriptions`, `limited_amount`) VALUES
(1,	'Giảm theo đơn hàng',	NULL,	NULL,	CONV('0', 2, 10) + 0,	NULL,	0),
(2,	'Giảm 10% cho khách mới',	NULL,	NULL,	CONV('0', 2, 10) + 0,	NULL,	0),
(3,	'Khách hàng thân thiết',	NULL,	NULL,	CONV('0', 2, 10) + 0,	NULL,	0),
(4,	'Voucher tháng 4',	25000000,	100,	CONV('1', 2, 10) + 0,	NULL,	0),
(5,	'Giảm 20% cho đơn hàng trên 1 triệu',	1000000,	NULL,	CONV('0', 2, 10) + 0,	NULL,	0),
(6,	'Ưu đãi tháng 3 giảm 100k/đơn hàng',	100000,	NULL,	CONV('1', 2, 10) + 0,	NULL,	0),
(7,	'Sale 15-3',	NULL,	NULL,	CONV('0', 2, 10) + 0,	NULL,	0),
(9,	'Hoàn tiền 20% cho mỗi đơn hàng',	10000000,	0,	CONV('0', 2, 10) + 0,	'Hoàn tiền 20% cho đơn hàng trên 10 triệu',	0),
(10,	'Giảm 999k cho đơn hàng đầu tiên',	NULL,	999000,	CONV('0', 2, 10) + 0,	'Giảm 999k cho người dùng mới',	0),
(11,	'Ưu đãi mua hè ',	NULL,	15,	CONV('1', 2, 10) + 0,	'Voucher 15% cho 10 người dùng mới',	10),
(12,	'Sale to cuối tháng',	5000000,	NULL,	CONV('0', 2, 10) + 0,	'Giảm 15% cho đơn từ 5 triệu',	0),
(13,	'Voucher khách hàng thân thiết',	NULL,	NULL,	CONV('0', 2, 10) + 0,	'Giảm 2 triệu trên tổng đơn hàng',	0),
(14,	'Hoàn tiền 10%',	NULL,	NULL,	CONV('0', 2, 10) + 0,	'Giảm 10% tổng giá trị đơn hàng',	0),
(15,	'Mua càng nhiều giảm càng sâu',	5000000,	NULL,	CONV('0', 2, 10) + 0,	'Giảm 1 triệu cho đơn từ 5 triệu',	0);

DELIMITER ;;

CREATE TRIGGER `a_i_promotion_type` AFTER INSERT ON `promotion_type` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'promotion_type'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_promotion_type` AFTER UPDATE ON `promotion_type` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'promotion_type';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_promotion_type` AFTER DELETE ON `promotion_type` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'promotion_type';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `promotion_user`;
CREATE TABLE `promotion_user` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name_promotion_user` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `discount_value` double DEFAULT '0',
  `is_used` tinyint(1) DEFAULT '0',
  `create_date` datetime DEFAULT NULL,
  `start_date` datetime DEFAULT NULL,
  `expiration_date` datetime DEFAULT NULL,
  `promotion_code` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `promotion_type` int DEFAULT NULL,
  `user_id` int DEFAULT NULL,
  `is_percent` tinyint(1) DEFAULT '1',
  `is_deleted` tinyint(1) DEFAULT '1',
  PRIMARY KEY (`id`) USING BTREE,
  KEY `fk_promotion_user_user_1` (`user_id`) USING BTREE,
  KEY `fk_promotion_user_promotion_type_1` (`promotion_type`) USING BTREE,
  CONSTRAINT `fk_promotion_user_promotion_type_1` FOREIGN KEY (`promotion_type`) REFERENCES `promotion_type` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_promotion_user_user_1` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `promotion_user` (`id`, `name_promotion_user`, `discount_value`, `is_used`, `create_date`, `start_date`, `expiration_date`, `promotion_code`, `promotion_type`, `user_id`, `is_percent`, `is_deleted`) VALUES
(1,	'Giảm theo đơn',	500000,	0,	'2023-03-04 12:00:00',	'2023-01-04 12:00:00',	'2023-03-06 12:00:00',	'ORDERSALE5',	1,	25,	0,	0),
(2,	'Ưu đãi khách hàng mới',	10,	0,	'2023-03-04 12:00:00',	'2023-01-30 12:00:00',	'2023-06-10 12:00:00',	'NEWCUSTOMER',	2,	1,	1,	0),
(3,	'Ưu đãi khách hàng mới',	10,	0,	'2023-03-04 12:00:00',	'2023-03-04 12:00:00',	'2023-06-10 12:00:00',	'NEWCUSTOMER',	2,	NULL,	1,	0),
(4,	'Voucher tháng 4',	20,	0,	'2023-03-04 12:00:00',	'2023-04-01 12:00:00',	'2023-04-30 23:59:59',	'APRILSALE',	4,	NULL,	1,	0),
(5,	'Sale 15-3',	2000000,	0,	'2023-03-04 12:00:00',	'2023-03-04 12:00:00',	'2023-03-30 12:00:00',	'MARCH15',	7,	25,	1,	1),
(6,	'Sale 15-4',	2000000,	0,	'2023-03-04 12:00:00',	'2023-04-01 12:00:00',	'2023-04-30 12:00:00',	'HAPPYAPRIL15',	4,	NULL,	0,	0),
(7,	'Hoàn tiền 20%',	20,	0,	'2023-03-04 12:00:00',	'2023-03-04 12:00:00',	'2023-09-04 12:00:00',	'REDEEM20',	9,	NULL,	1,	0),
(8,	'Ưu đãi mua hè ',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'SUMMER15',	11,	32,	1,	0),
(9,	'Ưu đãi mua hè ',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'SUMMER15',	11,	36,	1,	0),
(10,	'Ưu đãi mua hè ',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'SUMMER15',	11,	37,	1,	0),
(11,	'Ưu đãi mua hè ',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'SUMMER15',	11,	38,	1,	0),
(12,	'Ưu đãi mua hè ',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'SUMMER15',	11,	39,	1,	0),
(13,	'Ưu đãi mua hè ',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'SUMMER15',	11,	40,	1,	0),
(14,	'Ưu đãi mua hè ',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'SUMMER15',	11,	44,	1,	0),
(15,	'Sale to cuối tháng',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'APRILBIGSALE',	12,	36,	1,	0),
(16,	'Sale to cuối tháng ',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'APRILBIGSALE',	12,	37,	1,	0),
(17,	'Sale to cuối tháng',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'APRILBIGSALE',	12,	38,	1,	0),
(18,	'Sale to cuối tháng',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'APRILBIGSALE',	12,	39,	1,	0),
(19,	'Sale to cuối tháng ',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'APRILBIGSALE',	12,	40,	1,	0),
(20,	'Sale to cuối tháng',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'APRILBIGSALE',	12,	44,	1,	0),
(21,	'Voucher khách hàng thân thiết',	2000000,	0,	'2023-04-04 12:00:00',	'2023-04-01 00:00:00',	'2023-07-30 12:00:00',	'CUSTOMER04',	13,	35,	0,	0),
(22,	'Voucher khách hàng thân thiết',	2000000,	0,	'2023-04-04 12:00:00',	'2023-04-01 00:00:00',	'2023-07-30 12:00:00',	'CUSTOMER04',	13,	36,	0,	0),
(23,	'Voucher khách hàng thân thiết',	2000000,	0,	'2023-04-04 12:00:00',	'2023-04-01 00:00:00',	'2023-07-30 12:00:00',	'CUSTOMER04',	13,	37,	0,	0),
(24,	'Voucher khách hàng thân thiết',	2000000,	0,	'2023-04-04 12:00:00',	'2023-04-01 00:00:00',	'2023-07-30 12:00:00',	'CUSTOMER04',	13,	38,	0,	0),
(25,	'Voucher khách hàng thân thiết',	2000000,	0,	'2023-04-04 12:00:00',	'2023-04-01 00:00:00',	'2023-07-30 12:00:00',	'CUSTOMER04',	13,	39,	0,	0),
(26,	'Voucher khách hàng thân thiết',	2000000,	0,	'2023-04-04 12:00:00',	'2023-04-01 00:00:00',	'2023-07-30 12:00:00',	'CUSTOMER04',	13,	40,	0,	0),
(27,	'Voucher khách hàng thân thiết',	2000000,	0,	'2023-04-04 12:00:00',	'2023-04-01 00:00:00',	'2023-07-30 12:00:00',	'CUSTOMER04',	13,	44,	0,	0),
(28,	'Sale to cuối tháng',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'APRILBIGSALE',	12,	35,	1,	0),
(29,	'Voucher khách hàng thân thiết',	2000000,	0,	'2023-04-04 12:00:00',	'2023-04-01 00:00:00',	'2023-07-30 12:00:00',	'CUSTOMER04',	13,	25,	0,	0),
(30,	'Sale to cuối tháng',	15,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'APRILBIGSALE',	12,	25,	1,	0),
(31,	'Hoàn tiền 10%',	10,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'DISCOUNT10%',	14,	25,	1,	0),
(32,	'Hoàn tiền 10%',	10,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'DISCOUNT10%',	14,	35,	1,	0),
(33,	'Hoàn tiền 10%',	10,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'DISCOUNT10%',	14,	36,	1,	0),
(34,	'Hoàn tiền 10%',	10,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'DISCOUNT10%',	14,	37,	1,	0),
(35,	'Hoàn tiền 10%',	10,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'DISCOUNT10%',	14,	38,	1,	0),
(36,	'Hoàn tiền 10%',	10,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'DISCOUNT10%',	14,	39,	1,	0),
(37,	'Hoàn tiền 10%',	10,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'DISCOUNT10%',	14,	40,	1,	0),
(38,	'Hoàn tiền 10%',	10,	0,	'2023-04-04 12:00:00',	'2023-04-04 00:00:00',	'2023-06-30 12:00:00',	'DISCOUNT10%',	14,	44,	1,	0),
(39,	'Mua càng nhiều giảm càng sâu',	1000000,	0,	'2023-04-04 12:00:00',	'2023-04-15 00:00:00',	'2023-06-30 12:00:00',	'SALEOFF1504',	15,	25,	0,	0),
(40,	'Mua càng nhiều giảm càng sâu',	1000000,	0,	'2023-04-04 12:00:00',	'2023-04-15 00:00:00',	'2023-06-30 12:00:00',	'SALEOFF1504',	15,	44,	0,	0),
(41,	'Mua càng nhiều giảm càng sâu',	1000000,	0,	'2023-04-04 12:00:00',	'2023-04-15 00:00:00',	'2023-06-30 12:00:00',	'SALEOFF1504',	15,	35,	0,	0),
(42,	'Mua càng nhiều giảm càng sâu',	1000000,	0,	'2023-04-04 12:00:00',	'2023-04-15 00:00:00',	'2023-06-30 12:00:00',	'SALEOFF1504',	15,	40,	0,	0);

DELIMITER ;;

CREATE TRIGGER `a_i_promotion_user` AFTER INSERT ON `promotion_user` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'promotion_user'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_promotion_user` AFTER UPDATE ON `promotion_user` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'promotion_user';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_promotion_user` AFTER DELETE ON `promotion_user` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'promotion_user';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `rating`;
CREATE TABLE `rating` (
  `id` int NOT NULL AUTO_INCREMENT,
  `point` int DEFAULT NULL,
  `created_date` datetime DEFAULT NULL,
  `user_id` int DEFAULT NULL,
  `order_detail_id` int DEFAULT NULL,
  `content` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `product_id` int DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `order_detail_id` (`order_detail_id`),
  KEY `fk_rating_product_1` (`product_id`) USING BTREE,
  KEY `fk_rating_order_detail_1` (`order_detail_id`) USING BTREE,
  KEY `fk_rating_user_1` (`user_id`) USING BTREE,
  CONSTRAINT `fk_rating_order_detail_1` FOREIGN KEY (`order_detail_id`) REFERENCES `order_detail` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_rating_product_1` FOREIGN KEY (`product_id`) REFERENCES `product` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_rating_user_1` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `rating` (`id`, `point`, `created_date`, `user_id`, `order_detail_id`, `content`, `product_id`) VALUES
(41,	5,	'2023-04-14 15:20:40',	1,	57,	'',	98),
(42,	5,	'2023-04-14 16:06:08',	1,	61,	'',	95),
(43,	5,	'2023-04-15 14:50:51',	38,	76,	'Ship nhanh',	96),
(44,	5,	'2023-04-15 16:22:14',	26,	88,	'SẢN PHẨM NGON',	99),
(45,	5,	'2023-04-19 16:54:26',	1,	104,	'',	99),
(46,	5,	'2023-04-19 16:54:26',	1,	105,	'',	100),
(47,	5,	'2023-04-19 16:59:06',	1,	92,	'',	99),
(48,	4,	'2023-04-21 19:00:08',	44,	121,	'Sản phẩm tốt, đúng mẫu, good ',	96),
(49,	4,	'2023-04-23 23:01:50',	45,	148,	'Mua lúc sale, giảm được hơn 3 triệu',	100),
(50,	4,	'2023-04-23 23:01:50',	45,	149,	'Màu đẹp, máy ngon',	98),
(51,	4,	'2023-04-23 23:01:50',	45,	150,	'Giao hàng nhanh, đóng gói ổn',	100),
(52,	5,	'2023-04-23 23:11:21',	45,	154,	'Giảm giảm hời, nên mua',	117),
(53,	4,	'2023-04-23 23:17:14',	44,	147,	'good',	95),
(54,	5,	'2023-04-23 23:42:41',	45,	152,	'Tốt so với tầm giá',	109),
(55,	3,	'2023-04-23 23:42:41',	45,	153,	'Đời cũ nhưng giá hơi chát',	104),
(56,	5,	'2023-04-24 21:26:08',	1,	79,	'Tốt',	96),
(57,	5,	'2023-04-24 22:02:26',	1,	69,	'',	98),
(58,	5,	'2023-04-24 22:02:32',	1,	65,	'',	95),
(59,	5,	'2023-04-24 22:02:32',	1,	66,	'',	95),
(60,	3,	'2023-04-24 22:02:39',	1,	62,	'',	105),
(61,	2,	'2023-04-24 22:02:43',	1,	58,	'',	94),
(62,	2,	'2023-04-24 22:02:50',	1,	56,	'',	100),
(63,	2,	'2023-04-24 22:02:55',	1,	55,	'',	99),
(64,	2,	'2023-04-24 22:03:01',	1,	53,	'',	100),
(65,	2,	'2023-04-24 22:03:06',	1,	45,	'',	98),
(66,	3,	'2023-04-24 22:03:14',	1,	44,	'',	105);

DELIMITER ;;

CREATE TRIGGER `a_i_rating` AFTER INSERT ON `rating` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'rating'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_rating` AFTER UPDATE ON `rating` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'rating';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_rating` AFTER DELETE ON `rating` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'rating';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `refreshtoken`;
CREATE TABLE `refreshtoken` (
  `id` int NOT NULL AUTO_INCREMENT,
  `expiry_date` datetime NOT NULL,
  `token` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `user_id` int NOT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  KEY `tokenToAccount` (`user_id`) USING BTREE,
  CONSTRAINT `refreshtoken_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `refreshtoken` (`id`, `expiry_date`, `token`, `user_id`) VALUES
(1453,	'2023-05-22 22:15:50',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0YWluZ3V5ZW4iLCJleHAiOjE2ODQ3Njg1NDl9.4BQURJqp73U7szKjHr6v6kep_urUaUsPlE9tPZbFqwo',	44),
(1457,	'2023-05-23 12:23:46',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0YWluZ3V5ZW4iLCJleHAiOjE2ODQ4MTk0MjZ9.TNRq_NbHU85rudyx_CTj_5gNN6fVlQHB45ROLjoeh-w',	44),
(1468,	'2023-05-23 18:59:41',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ3b2xhZGUiLCJleHAiOjE2ODQ4NDMxODF9.GZlSCLUlMmzHfesb7FstBTFb_mVHs53i0Vz56Hz0hqk',	45),
(1469,	'2023-05-23 19:06:49',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ3b2xhZGUiLCJleHAiOjE2ODQ4NDM2MDl9.knKzUZnQbVA7JX25j4pnkPY0gQhIrmCKHCJV5v3iWzI',	45),
(1474,	'2023-05-24 14:33:08',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJqbmt6b25lQGdtYWlsLmNvbSIsImV4cCI6MTY4NDkxMzU4OH0.zeVOHJBTB0si_JuHikCVDdmEVr4alGlhU0KWKGeXAY0',	41),
(1478,	'2023-05-24 21:20:17',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJqbmt6b25lQGdtYWlsLmNvbSIsImV4cCI6MTY4NDkzODAxNn0.-REyctRGiwKvp93sEp7knfs7RmCgzxzk2-ZDpFkZtoo',	41),
(1479,	'2023-05-24 21:25:10',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwaHUiLCJleHAiOjE2ODQ5MzgzMTB9.j01HXvEtjadH9ovv5AejhHaEJP-4LP-2l65y3cVV7-Q',	1),
(1488,	'2023-05-24 22:01:45',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwaHUiLCJleHAiOjE2ODQ5NDA1MDV9.FtenwlHJftF4A0QPyS6cxp6JsqIdaGeEHhwsiQeJlvw',	1),
(1495,	'2023-05-24 22:42:06',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJuaGF0YWJjIiwiZXhwIjoxNjg0OTQyOTI1fQ.CGmzJLmWQ7sHp4ND6JgQswCX-pQQuq_ukWJ-dPLNQd0',	25),
(1497,	'2023-05-25 19:05:45',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJuaGF0YWJjIiwiZXhwIjoxNjg1MDE2MzQ0fQ.894C-rqCoVZ3-tcw9qkklidwAcEVGu4blF_Y-jDrVvU',	25),
(1504,	'2023-05-25 21:08:05',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJodXluaHZhbnZvbmcyMDAyQGdtYWlsLmNvbSIsImV4cCI6MTY4NTAyMzY4NH0.8q4tAYkp75OT3-909PAh3tT2wjn35NdoMn3S0EMB6sI',	36),
(1505,	'2023-05-25 21:19:42',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJsb25nIiwiZXhwIjoxNjg1MDI0MzgyfQ.3fJeXdOTPJ_3-SQihXc1O293hJiQsbZRw9t6ZsR8QT0',	26),
(1506,	'2023-05-25 21:21:47',	'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJsb25nIiwiZXhwIjoxNjg1MDI0NTA3fQ.9AsdHNcW07KphdZ_DfBfz1obYo9LjKt5pRl5o9ykPUA',	26);

DELIMITER ;;

CREATE TRIGGER `a_i_refreshtoken` AFTER INSERT ON `refreshtoken` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'refreshtoken'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_refreshtoken` AFTER UPDATE ON `refreshtoken` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'refreshtoken';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_refreshtoken` AFTER DELETE ON `refreshtoken` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'refreshtoken';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `role`;
CREATE TABLE `role` (
  `unique_id` int NOT NULL AUTO_INCREMENT,
  `role_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`unique_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `role` (`unique_id`, `role_name`) VALUES
(1,	'USER'),
(2,	'ADMIN');

DELIMITER ;;

CREATE TRIGGER `a_i_role` AFTER INSERT ON `role` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'role'; 						SET @pk_d = CONCAT('<unique_id>',NEW.`unique_id`,'</unique_id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_role` AFTER UPDATE ON `role` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'role';						SET @pk_d_old = CONCAT('<unique_id>',OLD.`unique_id`,'</unique_id>');						SET @pk_d = CONCAT('<unique_id>',NEW.`unique_id`,'</unique_id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_role` AFTER DELETE ON `role` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'role';						SET @pk_d = CONCAT('<unique_id>',OLD.`unique_id`,'</unique_id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `storage`;
CREATE TABLE `storage` (
  `id` int NOT NULL AUTO_INCREMENT,
  `storage_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `storage` (`id`, `storage_name`) VALUES
(1,	'64GB'),
(2,	'128GB'),
(3,	'256GB'),
(4,	'512GB'),
(5,	'1TB');

DELIMITER ;;

CREATE TRIGGER `a_i_storage` AFTER INSERT ON `storage` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'storage'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_storage` AFTER UPDATE ON `storage` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'storage';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_storage` AFTER DELETE ON `storage` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'storage';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `user`;
CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT,
  `email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `full_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `phone` varchar(13) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `create_date` datetime DEFAULT NULL,
  `update_date` datetime DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `user` (`id`, `email`, `full_name`, `phone`, `create_date`, `update_date`) VALUES
(1,	'synhatphu3@gmail.com',	'Phú',	'0985746756',	'2023-04-08 14:53:31',	'2023-04-24 21:25:35'),
(25,	'rifiweb707@dogemn.com',	'Pham Nhat Minh',	'0901234569',	'2023-04-09 04:25:04',	'2023-04-09 04:25:04'),
(26,	'truonghoanglong1308@gmail.com',	'Truong Hoang Long',	'0969777741',	'2023-04-09 04:25:04',	'2023-04-21 16:39:30'),
(28,	'testguestagain@gmail.com',	'Test Guest Again',	NULL,	'2023-04-10 14:41:46',	'2023-04-10 14:41:46'),
(29,	'ngocsamyd@gmail.com',	'Sâm Nguyễn Thị Ngọc',	NULL,	'2023-04-11 13:53:28',	'2023-04-11 13:53:28'),
(32,	'hieuhoang25102001td@gmail.com',	'Hieu Hoang',	'0776274144',	'2023-04-12 16:18:27',	'2023-04-15 15:53:51'),
(35,	'synhatphu2@gmail.com',	'Sỳ Nhật Phú',	'0365768578',	'2023-04-14 16:02:55',	'2023-04-15 00:28:51'),
(36,	'huynhvanvong2002@gmail.com',	'vọng huỳnh',	'0987132367',	'2023-04-15 13:41:25',	'2023-04-15 13:41:34'),
(37,	'hieuhoang251001td@gmail.com',	'Hoàng',	'0776274144',	'2023-04-15 13:42:59',	'2023-04-15 13:42:59'),
(38,	'longthps16784@fpt.edu.vn',	'Truong Hoang Long (FPL HCM)',	'0969777741',	'2023-04-15 14:25:48',	'2023-04-15 14:25:58'),
(39,	'phusnps19247@fpt.edu.vn',	'Sy Nhat Phu (FPL HCM)',	'0394758675',	'2023-04-15 14:53:46',	'2023-04-15 14:53:53'),
(40,	'hieuhvps19146@fpt.edu.vn',	'Hoàng Văn Hiếu',	'0776274144',	'2023-04-15 16:10:12',	'2023-04-15 16:10:12'),
(41,	'jnkzone@gmail.com',	'Tran',	'0901234567',	'2023-04-16 16:35:50',	'2023-04-16 16:36:23'),
(42,	'tiennt1407@gmail.com',	'Tien Nguyen',	'0937923174',	'2023-04-18 10:03:09',	'2023-04-18 10:03:46'),
(43,	'anhnhq1608@gmail.com',	'Anh Nguyễn',	NULL,	'2023-04-19 19:19:29',	'2023-04-19 19:19:29'),
(44,	'nguyenquoctai872@gmail.com',	'Tài Nguyễn',	'0987877222',	'2023-04-21 16:42:38',	'2023-04-21 20:13:54'),
(45,	'wolade8558@snowlash.com',	'wolade8558@snowlash.com',	'0898123456',	'2023-04-23 18:59:37',	'2023-04-23 18:59:37');

DELIMITER ;;

CREATE TRIGGER `a_i_user` AFTER INSERT ON `user` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'user'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_user` AFTER UPDATE ON `user` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'user';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_user` AFTER DELETE ON `user` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'user';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

DROP TABLE IF EXISTS `wishlist`;
CREATE TABLE `wishlist` (
  `id` int NOT NULL AUTO_INCREMENT,
  `product_id` int DEFAULT NULL,
  `user_id` int DEFAULT NULL,
  `update_date` datetime DEFAULT NULL,
  `create_date` datetime DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uq_user_prod` (`product_id`,`user_id`) USING BTREE,
  KEY `fk_wishlist_product_1` (`product_id`) USING BTREE,
  KEY `fk_wishlist_user_1` (`user_id`) USING BTREE,
  CONSTRAINT `fk_wishlist_product_1` FOREIGN KEY (`product_id`) REFERENCES `product` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_wishlist_user_1` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;

INSERT INTO `wishlist` (`id`, `product_id`, `user_id`, `update_date`, `create_date`) VALUES
(45,	97,	29,	'2023-04-11 15:45:01',	'2023-04-11 15:45:01'),
(47,	95,	40,	'2023-04-15 16:12:00',	'2023-04-15 16:12:00'),
(48,	96,	40,	'2023-04-15 16:12:01',	'2023-04-15 16:12:01'),
(50,	94,	26,	'2023-04-19 06:37:29',	'2023-04-19 06:37:29'),
(51,	95,	26,	'2023-04-19 06:37:30',	'2023-04-19 06:37:30'),
(52,	98,	26,	'2023-04-21 16:40:24',	'2023-04-21 16:40:24'),
(57,	95,	1,	'2023-04-22 12:48:17',	'2023-04-22 12:48:17'),
(59,	94,	44,	'2023-04-22 14:35:54',	'2023-04-22 14:35:54'),
(60,	96,	44,	'2023-04-22 14:35:59',	'2023-04-22 14:35:59'),
(61,	98,	45,	'2023-04-23 22:48:56',	'2023-04-23 22:48:56'),
(62,	105,	45,	'2023-04-23 22:49:41',	'2023-04-23 22:49:41'),
(63,	104,	45,	'2023-04-23 23:05:39',	'2023-04-23 23:05:39'),
(64,	109,	45,	'2023-04-23 23:05:40',	'2023-04-23 23:05:40'),
(68,	105,	41,	'2023-04-24 22:03:07',	'2023-04-24 22:03:07'),
(69,	95,	25,	'2023-04-24 22:24:49',	'2023-04-24 22:24:49');

DELIMITER ;;

CREATE TRIGGER `a_i_wishlist` AFTER INSERT ON `wishlist` FOR EACH ROW
BEGIN 						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'cvb'; 						SET @tbl_name = 'wishlist'; 						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>'); 						SET @rec_state = 1;						UPDATE `history_store` SET `pk_date_dest` = `pk_date_src` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d AND (`record_state` = 2 OR `record_state` = 1); 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_dest` = @pk_d; 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`,`record_state` ) 						VALUES (@time_mark, @tbl_name, @pk_d, @pk_d, @rec_state); 						END;;

CREATE TRIGGER `a_u_wishlist` AFTER UPDATE ON `wishlist` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25179 SECOND); 						SET @tbl_name = 'wishlist';						SET @pk_d_old = CONCAT('<id>',OLD.`id`,'</id>');						SET @pk_d = CONCAT('<id>',NEW.`id`,'</id>');						SET @rec_state = 2;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d_old, @rec_state );						ELSE 						UPDATE `history_store` SET `timemark` = @time_mark, `pk_date_src` = @pk_d WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d_old;						END IF; END;;

CREATE TRIGGER `a_d_wishlist` AFTER DELETE ON `wishlist` FOR EACH ROW
BEGIN						SET @time_mark = DATE_ADD(NOW(), INTERVAL 25180 SECOND); 						SET @tbl_name = 'wishlist';						SET @pk_d = CONCAT('<id>',OLD.`id`,'</id>');						SET @rec_state = 3;						SET @rs = 0;						SELECT `record_state` INTO @rs FROM `history_store` WHERE  `table_name` = @tbl_name AND `pk_date_src` = @pk_d;						IF @rs = 1 THEN 						DELETE FROM `history_store` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs > 1 THEN 						UPDATE `history_store` SET `timemark` = @time_mark, `record_state` = 3, `pk_date_src` = `pk_date_dest` WHERE `table_name` = @tbl_name AND `pk_date_src` = @pk_d; 						END IF; 						IF @rs = 0 THEN 						INSERT INTO `history_store`( `timemark`, `table_name`, `pk_date_src`,`pk_date_dest`, `record_state` ) VALUES (@time_mark, @tbl_name, @pk_d,@pk_d, @rec_state ); 						END IF; END;;

DELIMITER ;

-- 2023-04-25 14:25:44
